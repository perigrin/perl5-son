# ABOUTME: Negate and Complement reach the wire from ordinary Perl but had no
# ABOUTME: deparser rule, so a graph containing either could not be rendered.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub run_perl ($src) {
    my $f = "$dir/r." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $f 2>&1);
    unlink $f;
    return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f;
    return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ( $data && $data->{methods}{'main::__PROGRAM__'} ) {
        fail "$name: translates";
        return;
    }
    my $d   = SoN::Deparse->new;
    my $out = eval { $d->render($data) };
    unless ( defined $out ) {
        my $g = $d->gap // $@ // '(no reason)';
        $g =~ s/\n.*//s;
        fail "$name: renders";
        diag $g;
        return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# THE COVERAGE GATE PROVED REACH, NOT RENDERABILITY. t/op-coverage.t has a
# fixture producing both of these -- t/corpus/arithmetic.pl for Negate and
# t/corpus/bitwise.pl for Complement -- so both were known to be emitted and
# neither had a rule in Deparse.pm. Measured on pvm's adjacency-04_operators:
#
#     GAP: no rule for value node `Negate` (id 189)
#
# That is the documented limit of a reach gate stated as a defect: observing a
# node kind is not verifying it. A subject must be a live variable or perl
# folds the operation away before the producer sees an op at all.
round_trips( <<'SRC', 'unary minus on a live variable' );
my $n = 17;
my $neg = -$n;
print "$neg\n";
SRC

round_trips( <<'SRC', 'bitwise complement on a live variable' );
my $n = 12;
my $c = ~$n & 0xFF;
print "$c\n";
SRC

# NEGATION OF AN EXPRESSION must keep its operand grouped: `-$a + $b` is
# `(-$a) + $b`, and emitting the operand unparenthesized where it is itself a
# sum would change the answer.
round_trips( <<'SRC', 'negation of a sum keeps its grouping' );
my $a = 3;
my $b = 4;
my $x = -($a + $b);
print "$x\n";
SRC

round_trips( <<'SRC', 'complement composes with a shift' );
my $n = 5;
my $y = (~$n & 0xF) << 1;
print "$y\n";
SRC

done_testing;
