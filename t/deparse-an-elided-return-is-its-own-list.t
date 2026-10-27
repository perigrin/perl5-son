# ABOUTME: A sub's trailing list with no `return` is that list's operands, not
# ABOUTME: every value an earlier statement left on the simulated stack.

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

# `my $n = shift; ($n, 1)` returned ($n, $n, 1): the assignment's value, left
# on the stack in void context, was swept into the elided return's list
# (perl resets the stack at each statement). `my @a = f(4)` counted 3.
round_trips(<<'S', 'a trailing list after a scalar assignment');
sub f { my $n = shift; ($n, 1) } my @a = f(4); print scalar(@a), " @a\n";
S
round_trips(<<'S', 'after two statements, in list and scalar context');
sub f { my $n = shift; my $m = $n * 2; ($n, $m) } my @a = f(4); my $s = f(5); print "@a $s\n";
S

done_testing;
