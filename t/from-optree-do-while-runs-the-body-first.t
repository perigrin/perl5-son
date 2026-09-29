# ABOUTME: `do { BODY } while COND` runs BODY before the first test: it lowers
# ABOUTME: as BODY followed by `while (COND) { BODY }`, a top-tested loop.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

# A TIME LIMIT, as for every loop test: a wrong lowering can spin.
sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; diag producer_stderr(); return;
    }
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

# A BOTTOM-TESTED LOOP. perl compiles it as the body, an unstack, the test,
# and an `and` whose ->other jumps BACK to the body -- and the walker read
# that back edge as a branch arm that never converged: "void-context 'and'
# arm did not converge". Corpus 134 (and 006's `do { } while`).
round_trips(<<'SRC', 'a do-while whose test is false at once still runs once');
my $i = $ENV{N} // 0;
do { print "once" } while $i > 0;
print "\n";
SRC

round_trips(<<'SRC', 'a do-while that counts');
my $n = $ENV{N} // 3;
my $k = 0;
do { $k = $k + 1 } while $k < $n;
print "$k\n";
SRC

round_trips(<<'SRC', 'a do-until');
my $k = 0;
do { $k = $k + 2 } until $k >= 5;
print "$k\n";
SRC

done_testing;
