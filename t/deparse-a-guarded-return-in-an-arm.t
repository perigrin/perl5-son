# ABOUTME: A return guarded inside an if arm leaves from that arm: the rest of the sub
# ABOUTME: after the if is emitted once, after it, not again inside the arm.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

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


# THE INNER IF'S ARMS MEET ONLY AT THE FUNCTION EXIT -- one returns, one
# falls through to the outer if's join -- so its join was the exit, and its
# fall-through arm ran on past the outer join: the loop after the if was
# emitted inside the arm and again after it, `my $phi` declared twice.
# chalk's Schedule::Elaborate::_collect_chain_recursive is this shape. Inside
# a loop the renderer already spelled such an arm as its own `return`.
round_trips(<<'SRC', 'a guarded return in an arm, then a loop');
sub walk { my ($op, $xs) = @_; my @chain; if ($op eq "If" || $op eq "S") { push @chain, $op; return "r@chain" if $op eq "If"; } for my $c (@$xs) { push @chain, $c } "@chain" }
print walk("If", [1]), "|", walk("S", [2, 3]), "|", walk("X", [4]), "\n";
SRC

round_trips(<<'SRC', 'a guarded return in an arm, then more statements');
sub f { my ($x) = @_; my $s = "s"; if ($x > 0) { $s .= "p"; return "early$s" if $x > 5; } $s .= "t"; my $u = uc $s; return $u }
print f(9), "|", f(1), "|", f(-1), "\n";
SRC

round_trips(<<'SRC', 'a guarded return in the else arm');
sub f { my ($x) = @_; my $s = "s"; if ($x > 0) { $s .= "p" } else { $s .= "n"; return "neg" if $x < -5; } for my $i (1 .. 2) { $s .= $i } return $s }
print f(1), "|", f(-1), "|", f(-9), "\n";
SRC

done_testing;
