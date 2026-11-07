# ABOUTME: a ternary or an if whose arm pins (a tied read, an in-place whole assign) takes the
# ABOUTME: control path -- If, a Proj per arm, a Region -- and round-trips with perl's order.

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

my $th = q{package TH; sub TIEHASH { bless {}, shift } sub STORE { my ($s, $k, $v) = @_; $main::L .= "S$k"; $s->{$k} = $v } sub FETCH { my ($s, $k) = @_; $main::L .= "F$k"; $s->{$k} } package main; my %h; tie %h, "TH"; $h{a} = 1; $h{b} = 2; };
round_trips($th . q{my $c = shift // 1; my $x = $c ? $h{a} : $h{b}; print "$x $main::L\n";}, 'a tied read in a ternary arm');
round_trips($th . q{for my $c (1, 0) { my $x = $c ? $h{a} : $h{b}; print "$x $main::L\n" }}, 'a tied read in a ternary arm, in a loop');
round_trips($th . q{my $c = shift // 1; if ($c) { print $h{a} } else { print $h{b} } print " $main::L\n";}, 'a tied read in an if arm');
round_trips(q{my @e; my $r = \@e; for my $k (0,1) { if ($k) { @e = (0,4) } else { @e = (9) } } print "@$r\n";}, 'an in-place whole assign in an if arm in a loop');

done_testing;
