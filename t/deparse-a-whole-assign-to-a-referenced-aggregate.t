# ABOUTME: a whole assign to a my aggregate a reference was taken to is a store into it:
# ABOUTME: the reference sees the new contents, as perl's does -- it round-trips.

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

round_trips(q{my @e = (1); my $r = \@e; @e = (2, 3); print "@$r\n";}, 'an array, read through the reference');
round_trips(q{my %h = (a => 1); my $r = \%h; %h = (b => 2); print join(",", map { "$_=$r->{$_}" } sort keys %$r), "\n";}, 'a hash, read through the reference');
round_trips(q{my @e = (1); my $r = \@e; @e = (2, 3); push @$r, 4; print "@e\n";}, 'an array, written through the reference, read by name');
round_trips(q{my @e = (1); my $r = \@e; for my $i (1 .. 2) { @e = ($i, $i * 10) } print "@$r\n";}, 'assigned in a loop');
round_trips(q{my @e = (1, 2); my $r = \@e; @e = (@e, 3); print "@$r\n";}, 'a list that reads the array itself');

done_testing;
