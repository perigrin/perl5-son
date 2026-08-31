# ABOUTME: A builtin's declared operand type must reach the coercion pass.
# ABOUTME: `abs` wants Num, so a Boolean argument gets a Coerce[Boolean->Num].
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub nodes_for ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my $wire = JSON::PP->new->decode($json);
    return [ map { ( $wire->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $wire->{methods} // {} )->%* ) ];
}

# THE DEFECT. The builtin index declares `abs => { operands => ['Num'] }`, but
# the coercion pass asked `operand_type('Call', 0)` -- the GENERIC node name,
# shared by ~180 builtins -- so the declaration was never consulted. Every
# builtin's `operands` row was dead data: written, unit-tested, and unreachable
# from the pass that exists to act on it.
#
# A Boolean in a Num position is the case that shows it. `meet(Boolean, Num)`
# is None, and None ne Boolean, so the rule `meet(from,to) != from` FIRES --
# meet == None does not mean "no coercion exists", it means the two types are
# incomparable, which is exactly when a conversion is needed. Perl agrees:
# abs(true) is 1.
subtest 'a Boolean argument to abs is coerced to Num' => sub {
    my $nodes = nodes_for( <<'SRC', 'abs-bool' );
my $x = 5; my $y = 5;
my $b = ($x == $y);
my $n = abs($b);
print $n;
SRC

    my ($abs) = grep { $_->{op} eq 'Call'
                       && ( $_->{fields}{name} // '' ) eq 'abs' } $nodes->@*;
    ok $abs, 'the abs Call is in the graph' or return;

    my %by_id = map { $_->{id} => $_ } $nodes->@*;
    my @args  = map { $by_id{$_} // () } ( $abs->{inputs} // [] )->@*;

    my ($coerce) = grep { ( $_->{op} // '' ) eq 'Coerce' } @args;
    ok $coerce, 'abs receives a Coerce, not the raw Boolean';
    is $coerce->{stamp}, 'Num', 'and it lands on Num' if $coerce;
};

# The counterpart: an operand ALREADY at the requirement gets no Coerce.
# `meet(Int, Num) = Int`, which IS `from`, so the predicate declines. Without
# this the fix could pass by coercing everything unconditionally.
subtest 'an Int argument to abs is left alone' => sub {
    my $nodes = nodes_for( <<'SRC', 'abs-int' );
my $i = -5;
my $n = abs($i);
print $n;
SRC

    my ($abs) = grep { $_->{op} eq 'Call'
                       && ( $_->{fields}{name} // '' ) eq 'abs' } $nodes->@*;
    ok $abs, 'the abs Call is in the graph' or return;

    my %by_id = map { $_->{id} => $_ } $nodes->@*;
    my @args  = map { $by_id{$_} // () } ( $abs->{inputs} // [] )->@*;

    is scalar( grep { ( $_->{op} // '' ) eq 'Coerce' } @args ), 0,
        'no Coerce on an operand that already satisfies the requirement';
};

done_testing;
