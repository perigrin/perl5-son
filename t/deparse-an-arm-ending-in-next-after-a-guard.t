# ABOUTME: An arm that ends in a bare `next`, in the rest of a loop body after a
# ABOUTME: guarded `last`, keeps its own If and its edge to the latch.

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


# THE ARM `{ $c--; next }` HAS ONLY A STORE, so the rest-of-body walk took it
# for a value arm: its store became a ternary and its `next` an edge from the
# guard's own control. With the bare `last` after it, the loop had no way
# round and ran once -- 11 for perl's 31.
round_trips(<<'S', 'a while (1)');
sub f { my ($c)=@_; my $n=0; while (1) { $n++; last if $n > 9; if ($c > 0) { $c--; next } last } return $n }
print f(2), f(0), "\n";
S

round_trips(<<'S', 'a for (;;)');
sub f { my ($c)=@_; my $n=0; for (;;) { $n++; last if $n > 9; if ($c > 0) { $c--; next } last } return $n }
print f(2), f(0), "\n";
S

round_trips(<<'S', 'a while with a condition');
sub f { my ($c)=@_; my $n=0; while ($n < 20) { $n++; last if $n > 9; if ($c > 0) { $c--; next } last } return $n }
print f(2), f(0), "\n";
S

round_trips(<<'S', 'a reference walked down');
sub f { my ($cur)=@_; my $n=0; while (1) { $n++; last if $n > 9; if (ref $cur) { $cur = $cur->[0]; next } last } return $n }
print f([[3]]), f(3), "\n";
S

round_trips(<<'S', 'a print after the loop');
sub f { my ($c)=@_; my $n=0; while (1) { $n++; last if $n > 9; if ($c > 0) { $c--; next } last } print "$n "; return }
f(2); f(0); print "\n";
S

round_trips(<<'S', 'at top level');
my $c=2; my $n=0; while (1) { $n++; last if $n > 9; if ($c > 0) { $c--; next } last } print "$n\n";
S

round_trips(<<'S', 'a `next if` guard before the arm');
sub f { my ($c)=@_; my $n=0; while ($n < 50) { $n++; next if $n > 9; if ($c > 0) { $c--; next } last } return $n }
print f(2), f(0), "\n";
S

done_testing;
