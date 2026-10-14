# ABOUTME: A variable written on the right of a value-context && or || keeps the write
# ABOUTME: exactly when the right side ran, in a condition, an assignment or a loop test.

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


round_trips(<<'SRC', 'an increment on the right of && in an assignment');
sub f { my $n = shift; my $h = 0; my $r = ($n > 3 && $h++ < 8); return "$h" . ($r ? 1 : 0) }
print f(5), f(1), "\n";
SRC

round_trips(<<'SRC', 'an increment on the right of && in an if condition');
sub f { my $n = shift; my $h = 0; if ($n > 3 && $h++ < 8) { print "y" } return "$h" }
print f(5), f(1), "\n";
SRC

round_trips(<<'SRC', 'an assignment on the right of ||');
sub f { my $n = shift; my $h = 7; my $r = ($n || ($h = 2)); return "$h$r" }
print f(5), f(0), "\n";
SRC

round_trips(<<'SRC', 'an increment on the right of && in a loop body');
sub f { my $n = 0; my $h = 0; for my $i (1..5) { my $r = ($i > 3 && $h++ < 8); $n += $r ? 1 : 0 } return "$h $n" }
print f(), "\n";
SRC

round_trips(<<'SRC', 'an increment on the right of && in an if arm');
sub f { my ($a, $n) = @_; my $h = 0; if ($a) { my $r = ($n > 3 && $h++ < 8); print $r ? "t" : "f" } return $h }
print f(1, 5), f(1, 1), f(0, 5), "\n";
SRC

round_trips(<<'SRC', 'an increment on the right of && in a while condition');
sub th { my $n = shift; my $hops = 0; while ($n > 3 && $hops++ < 8) { $n = $n - 2 } return "$n $hops" }
print th(10), th(100), th(1), "\n";
SRC

round_trips(<<'SRC', 'the shape of chalk BackwardInference::_thread_through_coerce');
use Scalar::Util qw(blessed);
sub N::new { bless {op => $_[1], in => $_[2]}, $_[0] } sub N::operation { $_[0]{op} } sub N::inputs { $_[0]{in} }
sub th { my $node = shift; my $hops = 0; while ($node && blessed($node) && $node->operation eq "Coerce" && $hops++ < 8) { $node = ($node->inputs // [])->[0]; } return $node }
my $x = N->new("X", []); my $c = N->new("Coerce", [N->new("Coerce", [$x])]);
my $deep = $x; $deep = N->new("Coerce", [$deep]) for 1 .. 12;
print th($c)->operation, th($x)->operation, th($deep)->operation, "\n";
SRC

done_testing;
