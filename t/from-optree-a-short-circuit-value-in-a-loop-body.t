# ABOUTME: A value-context `&&` / `||` inside a loop body -- a compound test
# ABOUTME: guarding `next`, a default -- is a value, not a second loop condition.

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

# THE LOOP BODY HAD NO RULE FOR IT. A non-void and/or there was taken for
# the loop's own condition -- which was already consumed -- and refused
# "nested and/or inside a loop body": 93 skipped graphs in chalk's lib/,
# most of them `next unless defined $x && length $x`.
round_trips(<<'SRC', 'a compound test guarding next');
sub f { my @a = @_; my $n = 0; for my $x (@a) { next unless defined $x && length $x; $n++ } $n }
print f("a", undef, "", "b"), "\n";
SRC

# Operands with known stamps: a loop cannot yet carry an Unknown value
# (the separate "unstamped back-edge" refusal), which is not what this tests.
round_trips(<<'SRC', 'an or in value context inside a while');
my $t = 0; my $i = 0;
while ($i < 3) { my $v = $i || 10; $t += $v; $i++ }
print "$t\n";
SRC

round_trips(<<'SRC', 'a nested short-circuit guarding last');
sub h { my @a = @_; my $seen = ""; for my $x (@a) { last if $x && $x eq "stop"; $seen .= $x } $seen }
print h("a", "", "b", "stop", "c"), "\n";
SRC

# `next unless C` IS AN `or`, and only `and` was a guarded jump: the `or`
# was lowered as the loop's own test and the rest of the body dropped --
# `$n++` never ran, and nothing refused.
round_trips(<<'SRC', 'next unless, the plain form');
sub f { my $n = 0; for my $x (@_) { next unless $x > 1; $n++ } $n }
print f(1, 2, 3), "\n";
SRC

round_trips(<<'SRC', 'last unless');
sub f { my $s = ""; for my $x (@_) { $s .= $x; last unless $x } $s }
print f("a", "b", 0, "c"), "\n";
SRC

# A COMPOUND LOOP CONDITION is the same value: `while (A && B)` tests an
# And. It refused as "nested and/or" -- the loop's own test was the second
# and/or the walker met.
round_trips(<<'SRC', 'a compound while condition');
my ($i, $j, $r) = (0, 0, 0);
while ($i < 3 && $j < 5) { $r = $r + 1; $i = $i + 1; $j = $j + 2 }
print "$r $i $j\n";
SRC

# THE ARM'S MATCH IS THE ONE `$1` NAMES afterwards: read only when the `and`
# was true, which is when the match ran (comp/retainedlines.t's idiom).
round_trips(<<'SRC', 'a capture after a match in an and-arm, in a map');
my %seen = (b => 1);
my @k = map { (!$seen{$_} and /x(\d)/) ? $1 : () } qw(ax1 b ax2 c);
print "@k\n";
SRC

done_testing;
