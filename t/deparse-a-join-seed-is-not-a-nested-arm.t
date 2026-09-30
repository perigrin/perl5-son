# ABOUTME: A join variable is seeded only from a path that skips the branch -- never
# ABOUTME: from a nested arm, whose value is spelled ahead of the guard that protects it.

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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    if (!$data || $err =~ /skipped/) {
        fail "$name: translates"; diag $err; return;
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

# THE SEED WAS A NESTED ARM'S VALUE. The function exit joins three returns;
# the middle one is an arm of an If inside the outer one's arm, so it was
# not among the outer If's arms and was taken for the fall-through seed:
#
#     my $phi22 = (($_[0])->[0])->[0];      <- before the guard
#     if (!(ref(...) eq "ARRAY")) { ... }
#
# which died "Can't use string as an ARRAY ref" (chalk's Optimizer.pm).
round_trips(<<'SRC', 'a guarded deref is not evaluated before its guard');
use v5.42;
sub f($x) { my $c = $x->[0]; return 0 unless ref($c) eq "ARRAY"; return $c->[0] if $c->@* == 1; return 9 }
print f([[5]]), f([[5, 6]]), f([1]), "\n";
SRC

# A REAL FALL-THROUGH STILL SEEDS: `$v` keeps 1 on the path that skips the if.
round_trips(<<'SRC', 'a one-armed if still seeds from the skipped path');
sub f { my $v = 1; if ($_[0]) { $v = 2 } $v } print f(0), f(1), "\n";
SRC

done_testing;
