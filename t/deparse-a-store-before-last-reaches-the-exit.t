# ABOUTME: A store into a demoted lexical on the arm that leaves a loop with `last`
# ABOUTME: is seen after the loop: the break carries its memory to the loop's exit.

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


# A BREAK RECORDED ITS CONTROL AND ITS BINDINGS, NOT ITS MEMORY. A lexical
# passed to a sub lives in memory, so `$so = $i; last` stored where the exit
# never looked: the read after the loop took the memory from before it, and
# the store vanished. chalk's Bootstrap::Runtime searches @INC for chalk.so
# exactly so, and never found it.
round_trips(<<'SRC', 'a store, then last, read by a call');
sub load { "L:" . ($_[0] // "u") }
my $so; for my $i (1, 2, 3) { if ($i == 2) { $so = $i; last; } } print load($so), "\n";
SRC

round_trips(<<'SRC', 'in a sub, the loop running out');
sub load { "L:" . ($_[0] // "u") }
sub f { my $so; for my $i (@_) { if ($i == 9) { $so = $i; last; } } return load($so) }
print f(1, 9, 3), f(1, 2), "\n";
SRC

round_trips(<<'SRC', 'a while loop');
sub load { "L:" . ($_[0] // "u") }
my $so; my $i = 0; while ($i < 5) { $i++; if ($i == 3) { $so = $i; last } } print load($so), "\n";
SRC

done_testing;
