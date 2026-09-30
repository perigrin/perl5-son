# ABOUTME: `E // V` in a loop body or a branch arm is a value, built as the main
# ABOUTME: walk builds it -- a DefinedOr over the two operands -- rather than refused.

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

# "dor inside a loop body not yet lowered" -- 30 graphs in chalk's lib/,
# where the commonest is a default: `my $t = $h{$k} // 'Unknown'`.
round_trips(<<'SRC', 'a defined-or default bound in a foreach body');
sub f { my $s = ""; for my $x (@_) { my $v = $x // "u"; $s .= $v } $s }
print f(1, undef, 0, undef), "\n";
SRC

round_trips(<<'SRC', 'a defined-or read directly');
sub f { my $s = ""; for my $x (@_) { $s .= $x // "u" } $s }
print f(undef, 2, undef), "\n";
SRC

round_trips(<<'SRC', 'a defined-or over a hash element, in a while body');
my %h = (a => 1, c => 0); my @k = qw(a b c); my $i = 0; my $s = "";
while ($i < 3) { my $v = $h{$k[$i]} // "none"; $s .= "$v;"; $i++ }
print "$s\n";
SRC

# THE ARM WALKER HAD NONE EITHER: "arm stopped at `dor`" (17 graphs) for an
# if/else or ternary arm, and "void-context 'and' arm did not converge" for
# a one-armed if (20 graphs), which is the same stop one handler over.
for my $args ([1, 5], [1, undef], [0, 5]) {
    my $call = join ', ', map { $_ // 'undef' } @$args;
    round_trips(<<"SRC", "a defined-or in an if/else arm ($call)");
sub f { my (\$c, \$x) = \@_; my \$v; if (\$c) { \$v = \$x // "u" } else { \$v = "n" } \$v }
print f($call), "\\n";
SRC
    round_trips(<<"SRC", "a defined-or in a one-armed if ($call)");
sub f { my (\$c, \$x) = \@_; my \$v = "n"; if (\$c) { \$v = \$x // "u" } \$v }
print f($call), "\\n";
SRC
    round_trips(<<"SRC", "a defined-or in a ternary arm ($call)");
sub f { my (\$c, \$x) = \@_; return \$c ? (\$x // "u") : "n" }
print f($call), "\\n";
SRC
}

done_testing;
