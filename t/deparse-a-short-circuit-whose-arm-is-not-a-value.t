# ABOUTME: A short-circuit whose right side stores an element, leaves the loop, or returns
# ABOUTME: is a guard with a merged value; a loop body never reads it as its own condition.

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


sub refuses ($src, $why, $name) {
    graph_of($src);
    like producer_stderr(), $why, $name;
}

# A foreach's iteration test is consumed before its body is walked, so an
# and/or in the body is never the loop condition.
round_trips(<<'SRC', 'a foreach: last if A && an element increment');
sub f { my %s; my $c = 0; for my $x (1,2,3,2,5) { last if $x > 1 && $s{$x}++; $c++ } return $c }
print f(), "\n";
SRC

round_trips(<<'SRC', 'a while: last if A && an element increment');
sub f { my %s; my $c = 0; my $x = 0; while ($x < 9) { $x++; last if $x > 1 && $s{$x % 3}++; $c++ } return $c }
print f(), "\n";
SRC

round_trips(<<'SRC', 'a foreach: next unless A && !an element increment');
sub f { my %s; my @o; for my $x (@_) { next unless defined $x && !$s{$x}++; push @o, $x } return join ",", @o }
print f(1, undef, 2, 1, 3, 2), "\n";
SRC

# The value of `E || next` on the path that goes on is E.
round_trips(<<'SRC', 'a foreach: my $r = $x || next');
sub f { my $n = 0; for my $x (@_) { my $r = $x || next; $n .= $r } return $n }
print f(1, 0, 2), "\n";
SRC

# The carried sum adds an argument element, which has no stamp to join, so
# the scout leaves the sum's Phi unstamped.
round_trips(<<'SRC', 'a foreach: a summed my $r = $x || next');
sub f { my $n = 0; for my $x (@_) { my $r = $x || next; $n += $r } return $n }
print f(1, 0, 2), "\n";
SRC

round_trips(<<'SRC', 'a foreach: my $r = $x && last');
sub f { my $n = 0; for my $x (@_) { my $r = $x && last; $n++ } return $n }
print f(0, 0, 3, 0), "\n";
SRC

round_trips(<<'SRC', 'a foreach: my $r = $x // next');
sub f { my $n = 0; for my $x (@_) { my $r = $x // next; $n++ if $r eq "U" } return $n }
print f("U", undef, "V", "U"), "\n";
SRC

round_trips(<<'SRC', 'a foreach: my $r = $x // last');
sub f { my $n = 0; for my $x (@_) { my $r = $x // last; $n .= $r } return $n }
print f("a", "b", undef, "c"), "\n";
SRC

# Inside an if/else arm the same guards build their If where they stand.
round_trips(<<'SRC', 'an if arm: my $a = E // return X');
sub f { my ($h, $p) = @_; my $w; if ($p) { my $a = $h->{a} // return "none"; $w = $a + 1 } else { $w = 0 } return $w }
print f({a=>2},1), f({},1), f({},0), "\n";
SRC

round_trips(<<'SRC', 'an if arm: my $a = E || return X');
sub f { my ($h, $p) = @_; my $w; if ($p) { my $a = $h->{a} || return "none"; $w = $a + 1 } else { $w = 0 } return $w }
print f({a=>2},1), f({},1), f({},0), "\n";
SRC

round_trips(<<'SRC', 'an if arm: my $a = E && return X');
sub f { my ($h, $p) = @_; my $w; if ($p) { my $a = $h->{a} && return "some"; $w = 7 } else { $w = "u" } return $w }
print f({a=>2},1), f({},1), f({},0), "\n";
SRC

round_trips(<<'SRC', 'an if arm: the return reads a store made before the guard');
sub f { my ($h, $p) = @_; my $w = 5; if ($p) { $w = 1; my $a = $h->{a} // return "none$w"; $w = $a } return $w }
print f({a=>2},1), f({},1), f({},0), "\n";
SRC

# The rest of a loop body after `next unless` is walked as an arm.
round_trips(<<'SRC', 'a rest arm: my $r = $x // next');
sub f { my $n = 0; for my $x (@_) { next unless defined $x && length $x; my $r = $x // next; $n++ if $r eq "U" } return $n }
print f("U", undef, "V", "U"), "\n";
SRC

round_trips(<<'SRC', 'a rest arm: my $r = $x || last');
sub f { my $n = 0; for my $x (@_) { next unless defined $x; my $r = $x || last; $n .= $r } return $n }
print f("U", undef, "V", 0, "U"), "\n";
SRC

round_trips(<<'SRC', 'a rest arm: my $r = $x || return X');
sub f { my $n = 0; for my $x (@_) { next unless defined $x; my $r = $x || return "r$n"; $n .= $r } return $n }
print f("U", undef, "V", 0, "U"), f(1, 2), "\n";
SRC

round_trips(<<'SRC', 'a while rest arm: my $r = $x || next');
sub f { my $n = 0; my $i = 0; while ($i < @_) { my $x = $_[$i++]; next unless defined $x; my $r = $x || next; $n .= $r } return $n }
print f("U", undef, "V", 0, "U"), "\n";
SRC

# In the caller's context the arm's value is the condition on the path that
# falls through; the renderer has no rule for that merge yet.
refuses('sub f { my ($p, $x) = @_; if ($p) { return 1 if $x } else { 2 } } print f(1,1), f(1,0), f(0,0), "\n";',
    qr/GAP: short-circuit with a non-value arm inside an if\/else arm not yet lowered/,
    'a want-0 return-if ending an arm refuses');

# A die arm is not an exit record; it keeps its own refusal.
refuses('sub f { my ($h, $p) = @_; if ($p) { my $a = $h->{a} // die "none\n"; return $a } return 0 } print f({a=>2},1), f({},0), "\n";',
    qr/GAP: void-context 'and' arm did not converge/,
    'a // die in an if arm refuses');

# An element store in the arm is an effect: it runs only when the guard lets it.
round_trips(<<'SRC', 'a foreach: a value && whose right side increments an element');
sub f { my %s; my $c = 0; for my $x (@_) { my $v = $x > 1 && $s{$x}++; $c .= $v } return $c }
print f(1,2,3,2), "\n";
SRC

round_trips(<<'SRC', 'an if arm in a foreach: next unless A && !an element increment');
sub f { my %s; my @o; for my $x (@_) { if ($x) { next unless defined $x && !$s{$x}++; push @o, $x } } return join ",", @o }
print f(1, 0, 2, 1, 3, 2), "\n";
SRC

round_trips(<<'SRC', 'an if arm in a foreach: last if A && an element increment');
sub f { my %s; my $c = 0; for my $x (@_) { if ($x > 0) { last if $x > 1 && $s{$x}++ } $c++ } return $c }
print f(1,2,3,2,5), "\n";
SRC

# Ending a sub, the arm takes the caller's context: its store and its return
# are not one value, so it refuses rather than drop the store.
refuses('my %t; sub f { my ($c, $a, $b) = @_; if ($c) { if ($a && $b) { $t{$b} = $a; return } } } f(1, "P", 3); print join(",", map {"$_=$t{$_}"} keys %t), "\n";',
    qr/GAP: a short-circuit whose arm is not a single value is not yet lowered/,
    'a store-and-return arm ending a sub refuses');

done_testing;
