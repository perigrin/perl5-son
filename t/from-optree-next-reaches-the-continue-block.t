# ABOUTME: `next` joins the loop at its latch -- before the `continue` block and
# ABOUTME: the step -- from the body, from a guard, and from a second guard.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

# A TIME LIMIT: a loop whose step is lost on the `next` path never ends, and
# without one that hangs the suite instead of failing this test.
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

# THE CONTINUE BLOCK RUNS ON EVERY `next`. It was walked as trailing body
# statements, inside the rest arm of the `next if` guard, so the `next` path
# skipped it: c2 was missing. A SILENT wrong answer. Corpus 137.
round_trips(<<'SRC', 'a guarded next runs the continue block');
my $n = $ENV{N} // 5;
my $i = 0;
my @s;
while ($i < $n) {
    $i = $i + 1;
    next if $i == 2;
    last if $i == 4;
    push @s, "b$i";
} continue {
    push @s, "c$i";
}
print "@s\n";
SRC

# TWO `next` GUARDS. The second sits in the first one's rest arm, which the
# branch walker refused: "a loop control (`next`) inside a branch arm".
# Corpus 007.
round_trips(<<'SRC', 'two next guards in one body');
my @out;
for my $i (1 .. 6) {
    next if $i == 2;
    next if $i == 4;
    push @out, $i;
}
print "@out\n";
SRC

# A C-STYLE for's STEP IS ITS CONTINUE BLOCK, and `next` must reach it -- or
# the counter stops advancing on the `next` path.
round_trips(<<'SRC', 'next in a C-style for still steps');
my @out;
for (my $i = 0; $i < 6; $i = $i + 1) {
    next if $i % 2;
    push @out, $i;
}
print "@out\n";
SRC

# AN UNCONDITIONAL `next` JUMPS TO THE LATCH, not the unstack.
round_trips(<<'SRC', 'an unconditional next runs the continue block');
my $i = 0;
my $c = 0;
while ($i < 3) {
    $i = $i + 1;
    next;
    $c = 100;
} continue {
    $c = $c + 1;
}
print "$i $c\n";
SRC

done_testing;
