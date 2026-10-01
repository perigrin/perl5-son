# ABOUTME: A sub whose last statement is a loop returns perl's false -- the loop's last
# ABOUTME: failed test -- not a value its body computed on the final pass.

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

# THE BODY'S LAST VALUE LEAKED OUT as the sub's result: nothing popped what
# a plain foreach body left on the stack, so the Return took it -- evaluated
# AFTER the loop, over a counter past the end. chalk's CoreItemIndex
# `build_from_grammar` ends in a loop; its emission returned
# `$eff11->[$phi16]...` and died on an empty grammar: "Can't use an undefined
# value as an ARRAY reference" in 99 of chalk's test files.
#
# perl returns ONE value, its shared false (builtin::is_bool says so).
round_trips(<<'SRC', 'a sub ending in a foreach over a list');
use v5.42; no warnings 'experimental::builtin';
sub f { for my $x (@_) { my $y = $x * 2 } }
my @r = f(1, 2); my $s = f(3);
print scalar(@r), "[", $r[0], "][", $s, "]", builtin::is_bool($r[0]) ? "b" : "-", "\n";
SRC

round_trips(<<'SRC', 'a sub ending in a foreach over a range');
sub f { my $n = 0; for my $i (1 .. 3) { $n += $i } } my @r = f(); print scalar(@r), "[$r[0]]\n";
SRC

round_trips(<<'SRC', 'a sub ending in a while loop');
sub g { my $i = 0; while ($i < 2) { $i++ } } my @w = g(); print scalar(@w), "[$w[0]]\n";
SRC

round_trips(<<'SRC', 'a sub ending in a loop over nothing');
sub f { for my $x (@_) { 1 } } my @e = f(); print scalar(@e), "[$e[0]]\n";
SRC

done_testing;
