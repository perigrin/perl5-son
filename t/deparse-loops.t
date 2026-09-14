# ABOUTME: A Loop renders as a while, with its Phis initialised before it.
# ABOUTME: Verified by RUNNING the emitted program; a dropped iteration shows.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; return;
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

# A LOOP IS A DIAMOND THAT COMES BACK. Measured on `while ($i < 3) {...}`:
#
#     3 Loop    in=[0]     ci=0
#     4 Proj    in=[3]     index=1      <- the EXIT
#    12 Proj    in=[3]     index=0      <- the BODY
#     9 Phi     in=[8,18]  region=3     <- [initial, next]
#    11 NumLt   in=[9,10]  ci=3         <- the condition, pinned on the Loop
#
# so the pieces of a `while` are all there: the condition is what the Loop
# controls, the body is Proj 0's chain, and the Phi says what carries across
# an iteration. The Phi's first input is its value on entry and must be
# emitted BEFORE the loop; its second is the value at the bottom.
#
# THE COUNT IS THE CHECK. A loop that runs one time too few or too many still
# produces plausible-looking output, so every case below prints per iteration.
subtest 'a counted while loop' => sub {
    round_trips(<<'SRC', 'three iterations');
my $i = 0;
while ($i < 3) { print "$i\n"; $i = $i + 1; }
print "done\n";
SRC

    round_trips(<<'SRC', 'zero iterations');
my $i = 5;
while ($i < 3) { print "never\n"; $i = $i + 1; }
print "done\n";
SRC
};

# TWO CARRIED VALUES, so a Phi that reads the wrong one shows up as a wrong
# sum rather than a wrong count.
subtest 'two loop-carried values' => sub {
    round_trips(<<'SRC', 'a counter and an accumulator');
my $i = 0;
my $sum = 0;
while ($i < 4) { $sum = $sum + $i; $i = $i + 1; print "$i $sum\n"; }
print "final $sum\n";
SRC
};

# A CONDITIONAL INSIDE A LOOP -- the diamond and the back edge together, which
# is where a join that resumes at the wrong place stops being invisible.
subtest 'a branch inside a loop' => sub {
    round_trips(<<'SRC', 'if inside while');
my $i = 0;
while ($i < 5) {
    if ($i < 2) { print "low $i\n"; } else { print "high $i\n"; }
    $i = $i + 1;
}
print "done\n";
SRC
};

done_testing;
