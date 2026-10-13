# ABOUTME: A list declaration ahead of a loop that list-assigns the same slots round
# ABOUTME: trips: the declaration keeps its `my`, and the loop's assign does not redeclare.

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

# `my ($x, $y) = (0, 0)` floats to the prologue, which is rendered after the
# chain -- so the loop's `($x, $y) = ...` took the `my`, the prologue's did not,
# and the emission did not compile. perl prints `5 6`, `2 3`, `1 2`, `3 3`.
round_trips(<<'SRC', 'a swap through @_ in a foreach');
sub f { my ($x, $y) = (0, 0); for my $i (1..3) { ($x, $y) = ($y, $_[$i-1]) } return "$x $y" } print f(4,5,6), "\n";
SRC

round_trips(<<'SRC', 'a swap through the iterator in a foreach');
sub f { my ($x, $y) = (0, 0); for my $i (1..3) { ($x, $y) = ($y, $i) } return "$x $y" } print f(), "\n";
SRC

round_trips(<<'SRC', 'a swap in a while');
sub f { my ($x, $y) = (0, 0); my $i = 0; while ($i < 3) { ($x, $y) = ($y, $i); $i++ } return "$x $y" } print f(), "\n";
SRC

round_trips(<<'SRC', 'both slots from the iterator');
sub f { my ($x, $y) = (0, 0); for my $i (1..3) { ($x, $y) = ($i, $i) } return "$x $y" } print f(), "\n";
SRC

round_trips(<<'SRC', 'at file scope');
my ($x, $y) = (0, 0); for my $i (1..3) { ($x, $y) = ($y, $i) } print "$x $y\n";
SRC

done_testing;
