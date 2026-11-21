# ABOUTME: A hash read as a scalar -- its truth in a condition, `my $n = %h` -- is a Count of
# ABOUTME: it at a memory version, so a read before a store to the hash and one after differ.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# THE HASH ITSELF HANDED TO WHAT WANTS A SCALAR: a `my`, package or literal
# hash that is the condition of an If or a ternary, an operand of a logical
# or arithmetic operator, or coerced. No count node, so no memory version:
# `print %h ? "t" : "f"; delete $h{a}; print %h ? "t" : "f"` shared one
# TernaryExpr(HashLiteral) between the prints and said "tt" for perl's "tf".
sub hashes_read_as_scalars (@nodes) {
    my %by = map { $_->{id} => $_ } @nodes;
    my %scalar_slot = ( If => 1, TernaryExpr => 0, Not => 0, Coerce => 0 );
    my @bad;
    for my $user (@nodes) {
        my $op = $user->{op};
        my $in = $user->{inputs} // [];
        for my $slot ( 0 .. $#$in ) {
            my $n = $by{ $in->[$slot] // '' } // next;
            next unless ( $n->{fields}{sigil} // '' ) eq '%' && $n->{op} =~ /\A(?:PadAccess|HashLiteral|EntryDef)\z/;
            push @bad, "$op#$user->{id} reads $n->{op}#$n->{id}"
                if $op =~ /\A(?:Concat|Add|Subtract|Multiply|And|Or|Xor|DefinedOr|NumEq|NumGt|NumLt)\z/
                || exists $scalar_slot{$op} && $scalar_slot{$op} == $slot;
        }
    }
    return @bad;
}

for my $case (
    [ 'a ternary on a hash, each side of a delete',
        q{my %h = (a => 1); print %h ? "t" : "f"; delete $h{a}; print %h ? "t" : "f", "\n";}, 2 ],
    [ 'a hash assigned to a scalar, each side of a store',
        q{my %h = (a => 1); my $n = %h; $h{b} = 2; my $m = %h; print "$n $m\n";}, 2 ],
    # (the deparser binds no entry-version count of a `my` aggregate declared
    # with no value -- `my @a; my $n = @a; push @a, 1` is spelled after the
    # push too -- so this one's rendering is not perl's yet)
    [ 'a hash declared with no value, each side of a store',
        q{my %h; my $n = %h; $h{a} = 1; my $m = %h; print "$n $m\n";}, 2, 'an entry-version count of an unassigned my aggregate is not bound' ],
    [ 'a package hash as a ternary condition',
        q{our %g = (a => 1); print %g ? "t" : "f"; delete $g{a}; print %g ? "t" : "f", "\n";}, 2 ],
    [ 'a package hash never assigned, as a condition',
        q{our %g; print %g ? "t" : "f"; $g{a} = 1; print %g ? "t" : "f", "\n";}, 2 ],
    [ 'a package hash a called sub stores into',
        q{our %g; sub add { $g{ $_[0] } = 1; return } my $a = %g ? 1 : 0; add("k"); my $b = %g ? 1 : 0; print "$a $b\n";}, 2 ],
    [ 'if, unless and not',
        q{my %h; if (%h) { print "y\n" } else { print "n\n" } $h{a} = 1; print "full\n" if %h; print "empty\n" unless %h; print !%h ? "e" : "ne", "\n";}, 2 ],
    [ 'a logical operator and arithmetic',
        q{my %h = (a => 1, b => 2); my $x = %h && "yes"; my $y = %h + 1; print "$x $y\n";}, 1 ],
    [ 'a while on a hash',
        q{my %h = (a => 1, b => 2); my $i = 0; while (%h) { delete $h{ (sort keys %h)[0] }; $i++ } print "$i\n";}, undef ],
    [ 'a hash counted in a sub',
        q{sub n { my %l = @_; return %l ? scalar(%l) : -1 } print n(a => 1, b => 2), " ", n(), "\n";}, undef ],
) {
    my ( $what, $src, $versions, $deparse_todo ) = $case->@*;
    subtest $what => sub {
        my $data = graph_of($src) or return fail 'a wire';
        my @all  = map { $_->{nodes}->@* } values $data->{methods}->%*;
        is [ map { hashes_read_as_scalars( $_->{nodes}->@* ) } values $data->{methods}->%* ], [],
            'no hash is handed to what wants a scalar';
        my @counts = grep { $_->{op} eq 'Count' } $data->{methods}{'main::__PROGRAM__'}{nodes}->@*;
        @counts = grep { $_->{op} eq 'Count' } @all unless @counts;
        ok scalar(@counts), 'the wire counts the hash';
        is [ grep { !defined $_->{mem_in} } @counts ], [], q(every Count is of its hash, at a memory version);
        if ( defined $versions ) {
            my %seen = map { $_->{mem_in} => 1 } @counts;
            is scalar( keys %seen ), $versions, "they read $versions memory versions";
        }
        my $d   = SoN::Deparse->new;
        my $out = $d->render($data);
        ok defined $out, 'the deparser renders it' or diag $d->gap;
        my $todo = defined $deparse_todo ? todo($deparse_todo) : undef;
        is run_perl( $out // '' ), run_perl($src), 'and it prints what perl prints';
    };
}

# WHAT MUST NOT BECOME A COUNT: the hash `keys` counts, the one a call takes.
subtest 'keys in scalar context still reads the hash' => sub {
    my $src  = q{my %h = (a => 1, b => 2); our %g = (c => 3); my $k = keys %h; my $j = keys %g; print "$k $j ", scalar(%h), "\n";};
    my $data = graph_of($src) or return fail 'a wire';
    my @nodes = $data->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    my %by    = map { $_->{id} => $_ } @nodes;
    my @keys = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'keys' } @nodes;
    is scalar(@keys), 2, 'two keys calls';
    isnt $by{ $_->{inputs}[0] }{op}, 'Count', 'keys takes the hash, not its count' for @keys;
    my $d   = SoN::Deparse->new;
    my $out = $d->render($data);
    is run_perl( $out // '' ), run_perl($src), 'and it prints what perl prints';
};

done_testing;
