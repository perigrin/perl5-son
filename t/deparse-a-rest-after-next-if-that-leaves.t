# ABOUTME: The rest of a loop body after a `next if` that itself ends in `last` or `next`
# ABOUTME: leaves the loop from there; only the guard-taken path goes on to the latch.

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


# The emission must also be QUIET: a second `my @e` in one scope is a "masks
# earlier declaration" warning, and the masked variable is the defect.
sub emits_quietly ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}


# Merged as a fall-through, the `last` was lost and the loop ran on (42).
round_trips(q{my $s = 0; my $i=0; while ($i < 9) { $i++; next if $i < 3; $s += $i; last } print "$s\n";},
    'next if, then a rest ending in last');
round_trips(q{my $s = 0; my $i = 0; while ($i < 9) { $i++; next if $i < 3; $s += $i; last } continue { $s += 100 } print "$s\n";},
    'the same with a continue block, which the guard-taken path runs');
round_trips(q{my $s = 0; for my $i (1..9) { next if $i < 3; $s += $i; next } print "$s\n";},
    'next if, then a rest ending in next');
round_trips(q{my @r; for my $i (1..9) { next unless $i > 2; push @r, $i; last } print "@r\n";},
    'next unless, then a rest that pushes and leaves');

done_testing;
