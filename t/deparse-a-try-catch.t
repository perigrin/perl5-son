# ABOUTME: try/catch, in a sub, an if arm or a loop body: the body runs as an eval, the
# ABOUTME: catch arm sees the exception, and $@ is what it was before.

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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    if (!$data || $err =~ /skipped/) {
        fail "$name: translates"; diag $err; return;
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


sub refuses ($src, $why, $name) {
    graph_of($src);
    like producer_stderr(), $why, $name;
}

# chalk's Earley merges two values under try, and a catch that rethrows
# with context. It was refused in every arm and loop body ("untranslatable
# op inside an if/else arm (arm stopped at `entertrycatch`)").
my $ADD = <<'PRE';
use v5.42; no warnings;
package S { sub new { bless {}, shift } sub add { my ($s, $a, $b) = @_; die "clash\n" if $a eq $b; return "$a$b" } }
PRE

round_trips($ADD . <<'SRC', 'a merge under try, the catch rethrowing, in an if arm');
sub merge ($s, $x, $y) {
    my $out = "none";
    if (defined $x) {
        my $merged;
        try { $merged = $s->add($x, $y); } catch ($e) { die "Ambiguity for '$x': $e"; }
        $out = $merged;
    }
    return $out;
}
my $s = S->new;
print merge($s, "a", "b"), " ", merge($s, undef, "b"), " ", (eval { merge($s, "a", "a") } // "died: $@");
SRC

round_trips($ADD . <<'SRC', 'a merge under try in a loop body');
sub all ($s, @p) { my @r; for my $p (@p) { my $m; try { $m = $s->add(@$p); } catch ($e) { die "at @$p: $e"; } push @r, $m; } return "@r" }
my $s = S->new;
print all($s, [1, 2], [3, 4]), " ", (eval { all($s, [1, 2], [5, 5]) } // "died: $@");
SRC

round_trips(<<'SRC', 'a catch that handles, and $@ untouched');
use v5.42; no warnings;
sub g ($x) { die "bad $x\n" if $x > 1; return $x }
sub h ($x) { my $r = "n"; try { g($x); } catch ($e) { chomp $e; $r = "c:$e"; } return $r }
$@ = "before";
print h(1), " ", h(2), " [$@]\n";
SRC

# AN EARLY RETURN BEFORE AN IF/ELSE WHOSE ARM HOLDS THE TRY: the try's
# catch dies, so its If has no join of its own, and the ok arm was emitted
# on through the if/else's join into the exit -- which read the join's
# value before it was bound. chalk's Earley::_scan ends so.
round_trips(<<'SRC', 'a try in an if/else arm, after an early return');
use v5.42; no warnings;
my %c; $c{a} = 1;
sub f { 1 }
sub g ($k) { return if $k eq "z"; if (exists $c{$k}) { try { f() } catch ($x) { die "A: $x" } 1 } else { 2 } }
print g("a"), g("b"), "[", scalar(g("z")) // "u", "]\n";
SRC

refuses(<<'SRC', qr/GAP: a try body that returns or leaves a loop/, 'a return in a try body refuses');
use v5.42; no warnings;
sub f ($x) { try { return "t" if $x; } catch ($e) { } return "after" }
print f(1), f(0), "\n";
SRC

# A BODY'S REBIND STANDS BESIDE A CATCH THAT GOES ON when the catch arm
# rebinds the same variable: the die path's value is then the catch's.
round_trips(<<'SRC', 'a body and a catch that each assign the variable');
use v5.42; no warnings;
sub f ($d) { my $x = 0; try { die "no\n" if $d; $x = 1 } catch ($e) { $x = 2 } return $x }
print f(0), f(1), "\n";
SRC
# A REBIND BESIDE A CATCH THAT GOES ON holds what the body stored by the
# die: the variable lives in memory, and the emitted try keeps it so.
round_trips(<<'SRC', 'a body rebind beside a catch that leaves it');
use v5.42; no warnings;
sub f ($d) { my $x = 0; try { $x = 1; die "no\n" if $d; $x = 3 } catch ($e) { print "c" } return $x }
print f(0), f(1), "\n";
SRC
# chalk's Target::C keeps the emission's result, the error after the catch.
round_trips(<<'SRC', 'a result kept past a catch that records the error');
use v5.42; no warnings;
sub g ($d) { die "bad\n" if $d; return "ok" }
sub f ($d) { my ($r, $err); try { $r = g($d) } catch ($e) { $err = $e } return defined $err ? "E:$err" : "R:$r" }
print f(0), f(1);
SRC

# A LOOP CONTROL IN THE CATCH leaves the loop the try sits in: chalk's
# Target::C stops compiling an anon body with `catch ($e) { $ok = false;
# last }`. The arm walk had no loop to route it to and refused.
round_trips(<<'SRC', 'a catch that leaves the loop');
use v5.42; no warnings;
sub g { die "no\n" if $_[0] == 3; return $_[0] * 2 }
sub f { my @out; my $ok = 1; for my $s (@_) { my $c; try { $c = g($s) } catch ($e) { $ok = 0; last } push @out, $c } return "$ok:@out" }
print f(1, 2, 3, 4), " ", f(1, 2), "\n";
SRC
round_trips(<<'SRC', 'a catch that goes round the loop again');
use v5.42; no warnings;
sub g { die "no\n" if $_[0] == 3; return $_[0] * 2 }
sub f { my @out; my $bad = 0; for my $s (@_) { my $c; try { $c = g($s) } catch ($e) { $bad++; next } push @out, $c } return "$bad:@out" }
print f(1, 2, 3, 4), "\n";
SRC
round_trips(<<'SRC', 'a catch that leaves a while loop');
use v5.42; no warnings;
sub g { die "no\n" if $_[0] > 2; return $_[0] }
sub f { my $i = 0; my $t = 0; while ($i < 10) { $i++; try { my $v = g($i); $t += $v } catch ($e) { last } } return "$i $t" }
print f(), "\n";
SRC

# A CATCH THAT RETURNS FROM INSIDE A LOOP, its error unnamed: the `$@` read
# pinned where the eval ends had no reader and refused as an unbound
# statement.
round_trips(<<'SRC', 'a catch that returns from inside a loop');
use v5.42; no warnings;
sub g { die "no\n" if $_[0] == 3; return $_[0] * 2 }
sub f { my @out; for my $s (@_) { my $c; try { $c = g($s) } catch ($e) { return "R@out" } push @out, $c } return "@out" }
print f(1, 2, 3, 4), " ", f(1, 2), "\n";
SRC

done_testing;
