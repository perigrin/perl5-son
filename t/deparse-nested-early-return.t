# ABOUTME: An early return inside a nested branch makes the inner join the function exit.
# ABOUTME: The outer If's arms then converge past its own Proj, not at a Region between them.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; return;
    }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# A NESTED EARLY RETURN MAKES THE INNER JOIN THE FUNCTION EXIT. Measured on
# `if ($g) { if ($g>1) { print "a"; return 1 } } return 0`:
#
#      7 If     in=[6, 6]        Proj 8 (true) / Proj 14 (false)
#     11 If     in=[8, 10]       Proj 12 (true) / Proj 15 (false)
#     16 Region in=[14, 15]      the two FALSE arms
#     17 Region in=[13, 16]      the function exit
#     18 Phi    predecessors=[12, 16] region=17
#
# The outer If's arms do NOT converge at a Region between them: the true arm
# runs into the inner If and only rejoins at 16, which is also where the outer
# false arm lands. So _join_region -- which looks for the first Region both
# arms reach -- finds 16, the INNER join, and the outer If stops there while
# its own continuation is still to come.
#
# ALL THREE PATHS ARE EXERCISED, because a join taken at the wrong depth still
# produces a program: f(0) skips both, f(1) enters the outer only, f(2) enters
# both and returns early. Only running all three separates them.
subtest 'a nested early return' => sub {
    round_trips(<<'SRC', 'three paths through two ifs');
sub f {
    my $g = shift;
    if ($g) { if ($g > 1) { print "a\n"; return 1 } }
    return 0;
}
print f(0), f(1), f(2), "\n";
SRC
};

# THE SINGLE-LEVEL FORM ALREADY WORKED and must not regress -- it is the case
# the diamond logic was written for.
subtest 'a single-level early return' => sub {
    round_trips(<<'SRC', 'one if, returning early');
sub g {
    my $x = shift;
    if ($x > 1) { print "big\n"; return 1 }
    return 0;
}
print g(0), g(2), "\n";
SRC
};

done_testing;
