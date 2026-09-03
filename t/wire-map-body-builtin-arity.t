# ABOUTME: A map body calling a SCALAR builtin contributes exactly one value.
# ABOUTME: The allow-list was keyed on node kind, so every Call was refused.
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
    return ($said, $out, $err);
}

# THE PROPERTY IS ARITY, NOT NODE KIND -- which the existing allow-list says,
# and then keys on node kind anyway. Every builtin becomes a `Call`, so `lc`
# was swept up with genuinely variadic calls and refused:
#
#     map { lc($_) } ("A","B")     GAP: a Call may yield more than one value
#
# `lc` yields exactly one value, always. Measured across the family -- lc, uc,
# lcfirst, ucfirst, abs, int, sqrt, ord, chr, hex, oct, log, exp, cos, sin,
# quotemeta all yield 1, while reverse, sort and split yield N.
#
# A CALL THROUGH A CODEREF STAYS REFUSED, and correctly: `map { &{$sub}($_) }`
# in perl's own t/comp/proto.t calls a sub nobody can name at compile time, so
# its arity is genuinely unknowable. That is the case the GAP exists for.

# ASSERTS THE COUNT, NOT JUST THE ABSENCE OF A GAP. "it did not refuse" is
# satisfied by a graph that appends the wrong number of values, which is the
# exact miscompile the allow-list exists to prevent -- so the shape is checked:
# the ListAppend must carry the accumulator plus ONE contribution.
subtest 'the appended contribution is exactly one value' => sub {
    my ($said, $out, $err) = run_and_wire(
        'my @m = map { lc($_) } ("A","B"); print scalar(@m);', 'map-shape');
    is $said, '2', 'perl yields two values' or return;
    unlike $err, qr/unknown arity/, 'it lowers' or return;

    my $w = eval { JSON::PP->new->decode($out =~ s/\A[^{]*//sr) };
    ok $w, 'the wire parses' or return;
    my ($la) = grep { $_->{op} eq 'ListAppend' }
               map { $_->{nodes}->@* } values $w->{methods}->%*;
    ok $la, 'a ListAppend is built' or return;
    is scalar(($la->{inputs} // [])->@*), 2,
        'accumulator + exactly ONE contribution -- not a node standing for N';
};

subtest 'a scalar builtin in a map body lowers' => sub {
    for my $b ('lc($_)', 'uc($_)', 'abs($_)', 'int($_)', 'ord($_)') {
        my ($said, $out, $err) = run_and_wire(
            "my \@m = map { $b } (1,2); print scalar(\@m);", "map-$b" =~ s/\W//gr);
        is $said, '2', "perl maps two values through $b";
        unlike $err, qr/unknown arity/, "... and $b no longer refuses";
    }
};

# THE VARIADIC ONES MUST STILL REFUSE. reverse/sort/split yield N values, and
# appending one node that STANDS FOR N makes a consumer counting inputs read 1
# -- the miscompile the allow-list exists to prevent. A fix that admitted every
# builtin would trade a false refusal for a silent wrong count.
subtest 'a list-yielding builtin still refuses' => sub {
    for my $b ('reverse($_,$_)', 'sort($_,$_)') {
        my (undef, undef, $err) = run_and_wire(
            "my \@m = map { $b } (1,2); print scalar(\@m);", "mapv-$b" =~ s/\W//gr);
        like $err, qr/unknown arity/, "$b still refuses -- it may yield N";
    }
};

# A CALL TO A USER SUB STAYS REFUSED. Its arity is a property of the callee,
# not of the callsite, and the graph does not carry it -- measured, `sub g {42}`
# yields 1 while `sub g { ($_[0],$_[0]) }` yields 2 from an identical callsite.
subtest 'a user sub call still refuses' => sub {
    my (undef, undef, $err) = run_and_wire(
        'sub g { 42 } my @m = map { g($_) } (1,2); print scalar(@m);', 'map-user');
    like $err, qr/unknown arity/,
        'a named user sub refuses -- its arity is not on the wire';
};

done_testing;
