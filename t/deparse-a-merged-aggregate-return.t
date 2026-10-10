# ABOUTME: A sub returning a ternary merge with an aggregate arm (`wantarray ? @a : []`)
# ABOUTME: keeps both readings: the elements to a list caller, the count or ref to a scalar one.

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


round_trips('my @a=(1,2); sub f { wantarray ? @a : [] } my @x = f(); print scalar(@x), "\n";',
    'a lexical array arm, to a list caller');
round_trips('my @a=(1,2); sub f { wantarray ? @a : [] } my $x = f(); print ref($x), "\n";',
    'the reference arm, to a scalar caller');
round_trips('my @a=(1,2); sub f { $_[0] ? @a : [] } my $n = f(1); my $r = f(0); print "$n ", ref($r), "\n";',
    'the array arm reads as its count to a scalar caller');
round_trips('our @a=(1,2); sub f { wantarray ? @a : [] } my @x = f(); print "@x\n";',
    'a package array arm');
round_trips('my $r=[1,2,3]; sub f { wantarray ? @$r : [] } my @x = f(); print "@x\n";',
    'an array through a reference');
round_trips('my %h=(a=>1); sub f { wantarray ? %h : {} } my %x = f(); print join(",", %x), "\n";',
    'a hash arm');
round_trips('my @a=(1,2); sub f { return wantarray ? @a : [] } my @x = f(); print scalar(@x), "\n";',
    'an explicit return of the merge');
round_trips('sub k { my @l=(1,2,3); $_[0] ? @l : [] } my $s = k(0); my @t = k(1); print ref($s), " @t\n";',
    'an array declared in the sub, both callers');
round_trips('my @a=(1,2); sub f { wantarray ? @a : [] } for (1..2) { my @x = f(); print scalar(@x) } print "\n";',
    'called from a loop');

done_testing;
