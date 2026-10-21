# ABOUTME: `*name = \&code` under a package binds THAT package's glob, so the
# ABOUTME: sub it defines is the one calls in that package reach.

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

# THE GLOB'S NAME CARRIES ITS PACKAGE. The gv pushed its short name and the
# bind filed it under main, so `*rr = \&A::rr` in package B defined main::rr,
# and B's call to rr was refused as a call into nothing (chalk's
# LLVM::Context, which aliases LLVM's helpers this way).
round_trips(<<'SRC', 'a code alias bound in its own package');
package A; sub rr { "rr$_[0]" }
package B; *rr = \&A::rr; sub f { return rr($_[0]) }
package main; print B::f(3), "\n";
SRC
round_trips(<<'SRC', 'and main keeps its own');
package A; sub rr { "rr$_[0]" }
package main; *rr = \&A::rr; print rr(4), "\n";
SRC

done_testing;
