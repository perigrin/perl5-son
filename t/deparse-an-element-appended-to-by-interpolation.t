# ABOUTME: `$h->{k} .= "x$i"` (a multiconcat appending to an element) is the element read,
# ABOUTME: the strings appended, and a store back -- not a refusal; it round-trips.

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

round_trips(q{my $h = { log => "a" }; my $k = 1; $h->{log} .= "F$k"; $h->{log} .= "-$k-"; print "$h->{log}\n";}, 'a hash element through a reference');
round_trips(q{my @a = ("a"); my $k = 2; $a[0] .= "x$k"; print "$a[0]\n";}, 'an array element');
round_trips(q{my %h; my $k = 3; $h{z} .= "y$k"; print "$h{z}\n";}, 'an element not there yet');
round_trips(q{sub f { my ($s, $i) = @_; $s->{log} .= "F$i"; 1 } my $o = {}; f($o, 4); f($o, 5); print "$o->{log}\n";}, 'in a sub, through its argument');

done_testing;
