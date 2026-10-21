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

round_trips(<<'SRC', 'an assignment on the right of //');
sub f { my $n = shift; my $h = 7; my $r = ($n // ($h = 2)); return "$h$r" }
print f(5), f(undef), "\n";
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

# A `my` DECLARED ON THE RIGHT OF && has no binding before it, and the merge
# of the arm's rebinds passed it by: the variable was declared and never
# assigned (`none` for perl's `5`, at base too). Where the right side did
# not run it is undef. chalk's Earley::_complete tests `$_leo_enabled &&
# (my $leo = $leo_items{...}{...})`.
round_trips(<<'SRC', 'a my declared on the right of && in an if condition');
my %h = (a => { v => 5 }); sub f { my ($k, $on) = @_; my $r = "none"; if ($on && (my $x = $h{$k})) { $r = $x->{v} } return $r } print f("a", 1), f("b", 1), f("a", 0), "\n";
SRC
# A FIELD ON THE LEFT builds the && as real control flow, which merged the
# arm's bindings only where both sides had one -- the same loss, one path
# over. Earley::_complete's own shape.
round_trips(<<'SRC', 'a my declared on the right of && after a field');
use v5.42; no warnings; use experimental 'class';
class K { field $on :param = 1; field $items :param;
  method c ($rule, $origin) { my $r = "none"; if ($on && (my $leo = $items->{$rule}{$origin})) { $r = $leo->{value} } return $r } }
my $it = { r => { 7 => { value => "V" } } };
my $k = K->new(items => $it); print $k->c("r", 7), $k->c("r", 8), K->new(on => 0, items => $it)->c("r", 7), "\n";
SRC
# A FIELD FIRST READ IN THE ARM binds its slot to the field: no `my`, and
# no undef for it on the other path -- `$phi = %h` stored through a number.
round_trips(<<'SRC', 'a field hash first read on the right of &&, stored after');
use v5.42; no warnings; use experimental 'class';
class K { field $on :param = 1; field %leo;
  method c ($r, $o) { my $v = "none"; if ($on && (my $l = $leo{$r}{$o})) { $v = $l } $leo{$r}{$o} = "L$o"; return $v } }
my $k = K->new; print $k->c("a", 1), $k->c("a", 1), $k->c("a", 2), K->new(on => 0)->c("a", 1), "\n";
SRC
round_trips(<<'SRC', '... read in the else, where the right side may not have run');
sub f { my ($a, $b) = @_; my $r; if ($a && (my $x = $b)) { $r = "t$x" } else { $r = defined $x ? "d$x" : "u" } return $r } print f(1, 2), f(0, 2), f(1, 0), "\n";
SRC

done_testing;
