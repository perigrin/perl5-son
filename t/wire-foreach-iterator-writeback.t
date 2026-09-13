# ABOUTME: A foreach iterator is an ALIAS -- writing it mutates the source array.
# ABOUTME: The body binds an element copy, so the write needs an explicit store-back.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub run_and_wire ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $said = qx{$PERL $file 2>/dev/null};
    my $out  = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    my $w = (length $out && $out =~ /^\{/)
          ? eval { JSON::PP->new->decode($out) } : undef;
    my @n = $w ? ($w->{methods}{'main::__PROGRAM__'}{nodes} // [])->@* : ();
    return ($said, \@n, $err);
}

# PERL ALIASES THE ITERATOR, so a body write mutates the source in place.
# Measured on 5.42.0:
#
#     my @a=(1,2,3); for my $x (@a) { $x = $x*10 }   @a becomes 10 20 30
#     my @c=(1,2);   for (@c)       { $_ = $_+100 }  @c becomes 101 102
#     for my $v (values %h)         { $v = 42 }      the hash value changes
#
# The lowering reads element i into a Subscript and binds $x to it -- a COPY --
# so without a store-back the mutation is lost. That was refused rather than
# silently dropped, which was right.
#
# THE STORE SHAPE ALREADY EXISTS: `$a[0]=99` builds a 2-input lvalue Subscript,
# an Assign, and threads later reads on it. The write-back is that same shape
# with the loop's index Phi as the subscript.

subtest 'a body write reaches the array' => sub {
    # READ AN ELEMENT, not "@a". A whole-aggregate LIST read of a mutated
    # array is a separate, still-refused construct (the flatten shortcut would
    # take the pre-loop constants), so interpolating here would test that
    # refusal rather than this store.
    my ($said, $n, $err) = run_and_wire(
        'my @a=(1,2,3); for my $x (@a) { $x = $x*10 } print $a[1];', 'wb-basic');
    is $said, '20', 'perl mutates the array' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    # An Assign whose target is a Subscript is the store-back.
    my %by = map { $_->{id} => $_ } $n->@*;
    my @stores = grep {
        $_->{op} eq 'Assign'
          && (($by{ ($_->{inputs} // [])->[0] // '' }{op}) // '') eq 'Subscript'
    } $n->@*;
    ok scalar(@stores), 'an element store-back is built';
};

# THE $_ FORM ALIASES TOO, and it is the shape perl's own corpus uses.
subtest 'the $_ form writes back as well' => sub {
    my ($said, undef, $err) = run_and_wire(
        'my @c=(1,2); for (@c) { $_ = $_+100 } print $c[0];', 'wb-underscore');
    is $said, '101', 'perl mutates through $_' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers';
};

# A READ-ONLY BODY MUST NOT GAIN A STORE. Adding a write-back unconditionally
# would put a store in every foreach, which is a memory effect perl does not
# perform and would order reads that are currently free.
subtest 'a read-only body builds no store' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my @a=(1,2,3); my $t=0; for my $x (@a) { $t += $x } print $t;',
        'wb-readonly');
    is $said, '6', 'perl sums them' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    my %by = map { $_->{id} => $_ } $n->@*;
    my @stores = grep {
        $_->{op} eq 'Assign'
          && (($by{ ($_->{inputs} // [])->[0] // '' }{op}) // '') eq 'Subscript'
    } $n->@*;
    is scalar(@stores), 0, 'no element store in a read-only loop';
};

# A LIST READ OF THE MUTATED ARRAY STILL REFUSES, and it must: the flatten
# shortcut pushes the ArrayLiteral's ORIGINAL inputs, so `print "@a"` after the
# loop would join the pre-loop constants. Measured before the store recorded
# its mutation, that is exactly what it did -- while `$a[1]` correctly read 20,
# so the store was right and only the whole-aggregate read was blind.
# A LIST READ AFTER AN ALIAS WRITE OBSERVES THE WRITE. This refused for having
# "no node for the elements of @a as they now are"; PostfixDeref is that node
# and it takes a memory input, so the read threads to the in-loop Assign rather
# than to the pre-loop literal. Measured:
#
#     my @a=(1,2,3); for my $x (@a) { $x = $x*10 } print "@a"
#       perl : 10 20 30
#       graph: PostfixDeref(ArrayLiteral, Assign) feeding join -- the read is
#              threaded to the alias write, not to the original constants
subtest 'a list read observes the alias write' => sub {
    my ($out, $nodes, $err) = run_and_wire(
        'my @a=(1,2,3); for my $x (@a) { $x = $x*10 } print "@a";', 'wb-list');
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;
    is $out, '10 20 30', 'perl mutates through the alias' or return;

    my %by = map { $_->{id} => $_ } $nodes->@*;

    my ($read) = grep {
        $_->{op} eq 'PostfixDeref' && ($_->{inputs} // [])->@* >= 2
    } $nodes->@*;
    ok $read, 'the list read is a memory-threaded PostfixDeref' or return;

    my $mem = $by{ $read->{inputs}[1] };
    isnt $mem->{op}, 'MemStart',
        '... threaded to the write, not to the pre-loop memory';
};

# AN ALIAS WRITE CAN CHANGE THE TYPE, which is the case that distinguishes
# MODELLING the write from ignoring it. pvm raised it as a known gap in PSC:
# a checker that never models the substitution keeps the initialiser's type
# and happens to be right whenever the write preserves it -- and is wrong
# exactly here.
#
#     my $n = 42; foreach ($n) { $_ = "x" } print $n;    perl prints x
#
# B::SoN rebinds the scalar's slot, so the Print reads the Str.
subtest 'an alias write that changes the type is tracked' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my $n = 42; foreach ($n) { $_ = "x" } print $n;', 'wb-typechange');
    is $said, 'x', 'perl replaces the Int with a Str' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    my %by = map { $_->{id} => $_ } $n->@*;
    my ($pr) = grep { $_->{op} eq 'Print' } $n->@*;
    ok $pr, 'a Print is built' or return;
    my $node = $by{ ($pr->{inputs} // [])->[0] // '' };
    $node = $by{ ($node->{inputs} // [])->[0] // '' }
        while $node && $node->{op} eq 'Coerce';
    is +($node // {})->{stamp}, 'Str',
        'the read sees Str, not the Int the variable was initialised with';
};

done_testing;
