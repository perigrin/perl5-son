# ABOUTME: `next LABEL` and `last LABEL` from an inner loop are edges to the
# ABOUTME: named loop's latch and exit, not to the innermost loop's.

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

# THE LABEL WAS NEVER READ. `next OUTER` lowered as the inner loop's own
# `next` and `last OUTER` as its own `last`, so the outer loop ran every pass
# the program leaves -- a silent miscompile, not a refusal. Corpus 118.
round_trips(<<'SRC', 'next OUTER and last OUTER from an inner foreach');
my $c = $ENV{X} // 0;
my @l = ($ENV{A} // "a", "b", "c");
OUTER: foreach my $x (@l) {
    foreach my $y (@l) {
        next OUTER if $y eq "b";
        last OUTER if $c;
        print $y;
    }
}
print "\n";
SRC

round_trips(<<'SRC', 'last OUTER leaves both loops');
OUTER: for my $x (1..3) {
    for my $y (1..3) {
        last OUTER if $x * $y == 4;
        print "$x$y ";
    }
}
print "\n";
SRC

# THE LATCH MERGES A VALUE. `$n` reaches the outer latch two ways: by the
# `next OUTER` edge, with the inner loop's count, and never by falling off the
# body, whose `$n += 10` the edge skips.
round_trips(<<'SRC', 'next OUTER carries a value past the rest of the body');
my $n = 0;
OUTER: for my $x (1..3) {
    for my $y (1..3) {
        $n++;
        next OUTER if $y == 2;
    }
    $n += 10;
}
print "$n\n";
SRC

round_trips(<<'SRC', 'a label naming the innermost loop is the plain form');
INNER: for my $y (1..5) {
    next INNER if $y == 2;
    last INNER if $y == 4;
    print $y;
}
print "\n";
SRC

# THE STEP MOVES TO A continue BLOCK when a `next LABEL` names the loop: the
# jump skips the rest of the body, and the step is not the rest of the body.
# A test with an effect runs at the top, where the jump still reaches it.
round_trips(<<'SRC', 'next OUTER into a loop whose test has an effect');
my @q = (1, 2, 3);
OUTER: while (defined(my $x = shift @q)) {
    for my $y (1..3) {
        next OUTER if $y == 2;
        print "$x$y ";
    }
}
print "\n";
SRC

# THE BLOCK FORM, and the arm walk: after an unlabeled `next if`, the rest of
# the body is an arm, and its `last OUTER` is a statement modifier there.
round_trips(<<'SRC', 'a block-form last OUTER after a plain next if');
OUTER: for my $x (1..3) {
    for my $y (1..4) {
        next if $y == 1;
        if ($x + $y == 5) { last OUTER }
        print "$x$y ";
    }
}
print "\n";
SRC

round_trips(<<'SRC', 'next OUTER after a plain next if');
OUTER: for my $x (1..3) {
    for my $y (1..4) {
        next if $y == 1;
        next OUTER if $y == 3;
        print "$x$y ";
    }
    print "never ";
}
print "\n";
SRC

# AN UNCONDITIONAL `next OUTER;` still refuses, by name -- it was read as the
# inner loop's own `next`.
{
    my $data = graph_of(<<'SRC');
OUTER: for my $x (1..3) {
    for my $y (1..3) { print $y; next OUTER; }
}
SRC
    ok !($data && $data->{methods}{'main::__PROGRAM__'}),
        'an unconditional next OUTER does not translate';
    like producer_stderr(), qr/unconditional `next LABEL`/,
        '... and says why';
}

done_testing;
