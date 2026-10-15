# ABOUTME: A return under a guard in the false arm of an if, then a value the other paths
# ABOUTME: return, round trips: the value the inner if seeds stays when the outer if binds the join.

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
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
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


# The emission must also be QUIET: a second `my @e` in one scope is a "masks
# earlier declaration" warning, and the masked variable is the defect.
sub emits_quietly ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}


# The outer if's join Phi has a predecessor -- the merge of the outer true arm
# and the inner false arm -- that neither if pays in an arm. The inner if
# seeded the variable with its value; the outer if, finding every path to that
# merge under its own arms, wrote the declaration again without one, and the
# sub returned undef where perl returned "e".
round_trips(q{sub f { my ($a) = @_; if (!($a & 1)) { if ($a == 2) { return "x" } } return "e" } print join(",", map { f($_) } 1, 2, 4, 3), "\n";},
    'unless-arm with a guarded return, then a return');
round_trips(q{sub f { my ($a) = @_; if ($a & 1) { } else { if ($a == 2) { return "x" } } return "e" } print join(",", map { f($_) } 1, 2, 4, 3), "\n";},
    'an empty then-arm and a guarded return in the else');
round_trips(q{sub f { my ($a, $b) = @_; my $l = $a & 4; if (!($a & 8)) { if ($l && !($b & 4)) { return $b } if ($b & 4 && !$l) { return $a } } my $z = $a & 1; } print join(",", map { f(@$_) } [4,0],[0,4],[8,0],[1,1]), "\n";},
    'two guarded returns in the arm, then a fall-off value (chalk Structural::add)');
round_trips(q{sub f { my ($a) = @_; my $v = $a * 10; if (!($a & 1)) { if ($a == 2) { return "x" } } return $v } print join(",", map { f($_) } 1, 2, 4, 3), "\n";},
    'the returned value is computed before the if');

# The second if is emitted twice, once in each arm of the first, and its E
# arrives by its own merge -- the fall-through of the first if's false arm,
# which the arm reaches only by stepping over the nested if to its merge.
round_trips(q{sub f { my ($a) = @_; if (!($a & 1)) { if ($a & 2) { return "A" } } if ($a & 4) { if ($a & 1) { return "B" } } return "E" } print join(",", map { f($_) } 0, 1, 2, 3, 4, 5, 6, 7), "\n";},
    'two guarded blocks of returns in a row, then a return');

# A return reached along the chain inside such a copy pays the join variable
# its own input; the ifs that bound it pay only the arms they own, and this
# one returned it unset (chalk's Semiring::Structural::add, undef for 4).
round_trips(q{sub f { my ($l, $r) = @_; my $lc = $l & 4; my $rc = $r & 4; my $ll = $l & 8; my $rl = $r & 8; my $lm = $l & 32; my $rm = $r & 32; my $comp = $lc && $rc && (($lm && $rl && !$ll) || ($rm && $ll && !$rl)); if (!$comp) { if ($ll && !$rl) { return $r } if ($rl && !$ll) { return $l } } if ($lc && !$rc) { return $l } my $ld = $l & 16; my $rd = $r & 16; if ($lc && $rc) { if ($rd && !$ld) { return $l } if ($ld && !$rd) { return $r } } if ($lc && $rc) { if ($rm && !$lm) { return $l } if ($lm && !$rm) { return $r } } my $z = $l & 1; } print join(",", map { f(@$_) } [4,20],[20,4],[4,36],[36,4],[8,0],[0,8],[4,0],[5,5]), "\n";},
    'guarded returns after an unless block of them (chalk Structural::add)');

done_testing;
