# ABOUTME: `return X if C` leaves on the guard's TRUE Proj, so a sub with several
# ABOUTME: guarded returns renders; before, each exit hung off the pre-guard control.

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
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>$dir/err);
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

# THE EXIT RECORDED THE PRE-GUARD CONTROL. The and/or handler built the If
# and only its continue Proj, so the exit's edge came from the node BEFORE
# the If -- which then had two control successors. Measured on the first
# case:
#
#     10 If     in=[0, 9]
#     11 Proj   index=1 of 10          no index 0
#     15 Region in=[0, 11, 14]         Start is a predecessor
#
# and the deparser refused: "a control node with 2 successors". Corpus 030.
round_trips(<<'SRC', 'three guarded returns');
sub classify {
    return "zero" if $_[0] == 0;
    return "negative" if $_[0] < 0;
    return "positive";
}
print classify(0), " ", classify(-5), " ", classify(7), "\n";
SRC

round_trips(<<'SRC', 'return unless');
sub pos_or_zero {
    return 0 unless $_[0] > 0;
    return $_[0];
}
print pos_or_zero(-3), " ", pos_or_zero(4), "\n";
SRC

round_trips(<<'SRC', 'one guarded return');
sub f { return "early" if $_[0]; "late" }
print f(1), " ", f(0), "\n";
SRC

# AN ARM WITH AN EFFECT BUILT ITS If BEFORE THE WALK, and the exited path
# then built a second If on the continue Proj.
round_trips(<<'SRC', 'a guarded return whose arm prints first');
sub g {
    if ($_[0]) { print "side "; return "early" }
    return "late";
}
print g(1), " ", g(0), "\n";
SRC

# `E // return X` IS THE SAME SHAPE, built by the dor handler: an If on
# Not(Defined(E)) and only its continue Proj.
round_trips(<<'SRC', 'a defined-or return');
sub h {
    my $v = $_[0] // return "none";
    return "got $v";
}
print h(undef), " ", h(5), "\n";
SRC

done_testing;
