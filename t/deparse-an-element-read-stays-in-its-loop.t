# ABOUTME: An element read indexed by a loop's own Phi is read in that loop, never snapshotted
# ABOUTME: above it at a store before the loop -- where its index does not exist yet.

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

# A READ IN A LOOP IS READ IN THE LOOP. `$l[$i]` in a foreach after an eval
# whose body stores was snapshotted at that store -- inside the eval, above
# the loop that makes $i -- and the emission did not compile (corpus 006).
round_trips(<<'SRC', 'an element read in a loop after a store in an eval');
eval { $g = 1; die "x\n" };
exit 3 if $r;
foreach my $x (@l) { redo if $r; print "-f$x" }
print "[$g]\n";
SRC
round_trips(<<'SRC', 'and with lexicals');
our $g = 0; my $r = $ENV{NO_SUCH_VAR} // 0; my @l = ("a", "b");
eval { $g = 1; die "x\n" };
exit 3 if $r;
foreach my $x (@l) { redo if $r; print "-f$x" }
print "[$g]\n";
SRC

done_testing;
