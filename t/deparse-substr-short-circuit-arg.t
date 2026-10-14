# ABOUTME: substr counts a short-circuit argument: the null over its //, ||
# ABOUTME: or && is a real operand, so the string is not left behind on the stack.

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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK
//mr;
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
        my $g = $d->gap // '(no reason)'; $g =~ s/
.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---
$out--- got ---
$got--- want ---
$want";
}
round_trips(<<'P', 'a // offset');
my $v = "abc"; my $n; my $t = substr($v, $n // 1); print "$t\n";
P

round_trips(<<'P', 'a || length under push');
my $v = "abcdef"; my $n = 0; my @p; push @p, substr($v, 1, $n || 2); print "@p\n";
P

round_trips(<<'P', 'pos() // 0, the tail after a match');
my $v = "ab=cd"; $v =~ /=/g; print substr($v, pos($v) // 0), "\n";
P

done_testing;
