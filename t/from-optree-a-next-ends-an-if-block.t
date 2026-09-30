# ABOUTME: `if (C) { ...; next }` in a loop body: the arm's `next` is an edge to
# ABOUTME: the loop's latch, and the rest of the body runs only on the other path.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

# A TIME LIMIT, as for every loop test: a wrong lowering can spin.
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
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; diag producer_stderr(); return;
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

# A BARE `next` ENDING AN ARM refused -- "a loop control (`next`) inside a
# branch arm" -- where `next if C` in the same place lowered: 64 graphs in
# chalk's lib/, the commonest being an if-block that does some work and
# moves on.
round_trips(<<'SRC', 'an if-block that ends in next');
sub f { my ($n, $m) = (0, 0); for my $x (@_) { if ($x == 2) { $n++; next } $m++ } "$n $m" }
print f(1, 2, 3, 2), "\n";
SRC

round_trips(<<'SRC', 'an else that ends in next');
sub f { my $s = ""; for my $x (@_) { if ($x) { $s .= "y" } else { $s .= "n"; next } $s .= "." } $s }
print f(1, 0, 1), "\n";
SRC

round_trips(<<'SRC', 'an else that ends in last');
sub f { my $s = ""; for my $x (@_) { if ($x) { $s .= "y" } else { $s .= "n"; last } $s .= "." } $s }
print f(1, 1, 0, 1), "\n";
SRC

round_trips(<<'SRC', 'next ending an arm in a while, with a counter');
my ($i, $odd) = (0, 0);
while ($i < 6) { $i++; if ($i % 2 == 0) { next } $odd++ }
print "$i $odd\n";
SRC

done_testing;
