# ABOUTME: A break pays its exit values all at once: a payment that reads another slot
# ABOUTME: reads it as it was on the break path, not as an earlier payment left it.

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

# `$p = $p*2; $q = $q + $p*2; last` read the paid $p (16 47 for 16 31).
round_trips(q{my ($p,$q)=(1,1); for my $i (1..9) { $p *= 2; $q += $p; last if $q > 25 } print "$p $q\n";},
    'a last-if whose second slot reads the first');
round_trips(q{my ($p,$q)=(1,1); for my $i (1..9) { $p *= 2; $q += $p; if ($q > 25) { last } else { next } } print "$p $q\n";},
    'an if/else of last and next, the second slot reading the first');
round_trips(q{my ($p,$q)=(1,1); for my $i (1..9) { $p *= 2; $q += $p; last if $q > 25; last if $p > 100 } print "$p $q\n";},
    'two last-ifs, the first taken');
round_trips(q{my ($p,$q)=(1,1); for my $i (1..9) { $p *= 2; $q += $p; last if $q > 99; last if $p > 4 } print "$p $q\n";},
    'two last-ifs, the second taken');
round_trips(q{my ($a,$b)=(1,2); my $i=0; while ($i < 9) { $i++; ($a,$b)=($b,$a+$b); last if $b > 20 } print "$a $b $i\n";},
    'a swap then a last-if');
round_trips(q{my ($p,$q)=(1,1); for my $i (1..9) { $p *= 2; $q += $p; if ($q > 25) { $q .= "!"; last } } print "$p $q\n";},
    'an if-block that writes then leaves');

done_testing;
