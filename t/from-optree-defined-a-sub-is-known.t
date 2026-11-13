# ABOUTME: `defined &NAME` asks whether the sub exists, known when the program cannot
# ABOUTME: change it while it runs; it was Defined(the name string): always true.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub write_src ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return $f;
}

sub run_perl ($f) { return scalar qx(/usr/bin/timeout 10 $^X $f 2>/dev/null) }

sub producer_stderr ($src) {
    my $f = write_src($src);
    qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err >/dev/null);
    open my $e, '<', "$dir/err" or return ''; local $/; return <$e> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $f    = write_src($src);
    my $want = run_perl($f);
    my $j    = qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err);
    open my $e, '<', "$dir/err" or die; my $err = do { local $/; <$e> } =~ s/^\S+ syntax OK\n//mr;
    is $err, '', "$name: the producer says nothing" or return;
    my $d   = SoN::Deparse->new;
    my $out = $d->render(JSON::PP->new->decode($j));
    ok defined $out, "$name: renders" or diag($d->gap), return;
    is run_perl(write_src($out)), $want, "$name: runs as perl does"
        or diag "--- emitted ---\n$out";
}

# `defined &nope` printed y for perl's n.
round_trips(q{sub here { 1 } print defined &here ? "y" : "n"; print defined &nope ? "y" : "n"; print "\n";},
    'a sub with a body, and none');
round_trips(q{print defined &re::is_regexp ? "y\n" : "n\n";},
    'a sub perl itself defines (XS)');
# t/test.pl's: the old-perl fallback never runs, so its eval is never walked.
round_trips(q{my $l = 1; eval 'sub re::is_regexp { 1 }' if !defined &re::is_regexp; print "ok $l\n";},
    'an arm a known condition never runs');

# THE PROGRAM MAY CHANGE IT AS IT RUNS: refused by name.
like producer_stderr(q{*late = sub { 1 }; print defined &late ? "y\n" : "n\n";}),
    qr/GAP: `defined &late`/, 'a sub assigned to a glob';
like producer_stderr(q{sub here { 1 } undef &here; print defined &here ? "y\n" : "n\n";}),
    qr/GAP: `defined &here`/, 'a sub undefined';

done_testing;
