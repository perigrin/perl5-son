# ABOUTME: `while (my $l = <FH>)` pins an EFFECT and a test on the loop, not two tests.
# ABOUTME: The readline must run each iteration; the Defined over it is the condition.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(timeout 10 $^X $f 2>&1); unlink $f; return $out;
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

# TWO NODES PINNED ON A LOOP IS NOT TWO CONDITIONS. Measured on
# `while (my $line = <R>) { ... }`:
#
#     Loop 22   projs=[(23,1), (33,0)]
#       cond: 30 Call    [9]   name=readline
#       cond: 31 Defined [30]
#
# The readline is an EFFECT that must run once per iteration -- it advances
# the handle -- and the Defined over it is the actual test. The emitter
# required exactly one node pinned on the Loop and refused.
#
# THE LINE COUNT IS THE CHECK. A loop that evaluates the readline twice per
# iteration, or hoists it out, still prints lines -- just the wrong ones. So
# every case reports what it read, in order.
subtest 'while over a filehandle' => sub {
    round_trips(<<'SRC', 'two lines, read in order');
my $f = "wlr.$$.tmp";
open(W, ">$f"); print W "a\n"; print W "b\n"; close(W);
open(R, "<$f");
while (my $line = <R>) { print "got:$line" }
close(R);
unlink $f;
SRC

    round_trips(<<'SRC', 'an empty file reads nothing');
my $f = "wle.$$.tmp";
open(W, ">$f"); close(W);
open(R, "<$f");
my $n = 0;
while (my $line = <R>) { $n = $n + 1 }
close(R);
unlink $f;
print "n=$n\n";
SRC
};

# A PLAIN CONDITION MUST NOT REGRESS -- one node pinned on the Loop is the
# common case.
subtest 'a plain while still round-trips' => sub {
    round_trips(<<'SRC', 'a counted while');
my $x = 0;
while ($x != 3) { $x = $x + 1 }
print "x=$x\n";
SRC
};

done_testing;
