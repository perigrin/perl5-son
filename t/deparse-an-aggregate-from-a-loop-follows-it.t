# ABOUTME: A named aggregate built from a loop's result -- `my %h = map {...} @l` -- is
# ABOUTME: declared after the loop that computes it, not hoisted above it.

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

# THE AGGREGATE PROLOGUE LACKED THE ASSIGN LOOP'S LOOP-PHI RULE, so a hash
# holding a map's accumulator was declared above the map: `my %H = (@phi56)`
# before `my @phi56 = ()` -- undeclared under strict (chalk's
# TypedInvariant.pm), and empty without it.
round_trips(<<'SRC', 'a hash built by map');
my @l = qw(a b); my %h = map { $_ => 1 } @l; print join(",", sort keys %h), "\n";
SRC

round_trips(<<'SRC', 'a hash built by map, shared with a sub');
my @l = qw(a b); my %h = map { $_ => 1 } @l; sub has { $h{$_[0]} ? "y" : "n" } print has("a"), has("c"), "\n";
SRC

done_testing;
