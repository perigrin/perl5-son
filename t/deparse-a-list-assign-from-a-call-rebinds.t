# ABOUTME: A list assign from a call into declared scalars rebinds them: the
# ABOUTME: call's arity is unknown, but the targets hold whatever perl gave them.

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


# `($P) = @_` INTO A DECLARED SCALAR -- a package scalar or an earlier `my` --
# is not the padrange form, so nothing bound the targets: one target was
# stored the whole @_ (its count, 1 for "abc") and two were dropped.
# A CALL HAS NO POSITIONS, so the targets were left alone -- which for a
# `my (...) = g()` leaves each bound to its own slot, and for scalars
# declared EARLIER leaves each bound to its old value: `($lo, $used) = g();
# $used += 1` printed ` 1` for perl's `5 3`. chalk's LLVM::Context compiles
# a regex class so, in an if arm.
round_trips(<<'S', 'two declared lexicals from a call');
sub g { (5, 2) } sub f { my ($lo, $used); ($lo, $used) = g(); $used += 1; "$lo $used" } print f(), "\n";
S
round_trips(<<'S', 'one declared lexical from a call, in an arm');
sub g { (5, 2) } sub f { my $lo = 0; if ($_[0]) { ($lo) = g(); } "$lo" } print f(1), f(0), "\n";
S
round_trips(<<'S', 'two declared lexicals from a call in one arm, a list in the other');
sub g { return (65 + $_[0], 2) }
sub f { my ($c) = @_; my ($lo, $used); if ($c) { ($lo, $used) = g($c); $used += 1 } else { ($lo, $used) = (ord("a"), 1) } my $k = 10 + $used; return "$lo $used $k" }
print f(1), " | ", f(0), "\n";
S
round_trips(<<'S', 'declared lexicals from a call in a loop');
sub g { ($_[0] * 2, $_[0] + 1) } sub f { my ($a, $b) = (0, 0); my $s = ""; for my $i (1 .. 3) { ($a, $b) = g($i); $s .= "$a,$b;" } "$s$a$b" } print f(), "\n";
S
round_trips(<<'S', 'declared lexicals from a builtin of unknown arity');
sub f { my ($k, $v); ($k, $v) = split /=/, $_[0]; "$k:" . ($v // "u") } print f("a=b"), f("c"), "\n";
S

# A CALL STAMPED AS A REFERENCE is still a list on the right of a list
# assign: `($r) = k($x)` with k returning `\$_[0]` was spelled `$r = ...`,
# the count, and `$$r` died on it.
round_trips(q{sub k { return \$_[0] } sub f { my $x = 3; my $r; ($r) = k($x); $$r = 9; return $x } print f(), "\n";},
    'a list assign from a call returning a reference');

done_testing;
