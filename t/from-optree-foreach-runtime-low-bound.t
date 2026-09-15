# ABOUTME: `for my $i ($lo..$hi)` with a runtime LOW bound lowers like any range.
# ABOUTME: The induction Phi's init is the low bound, runtime or not.

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

# THE REFUSAL WAS STALE. It gave two reasons -- "the induction Phi init would
# be a runtime value whose stamp is not propagated through the back-edge (the
# loop-carried-stamp fixpoint)" and "the range's flip/flop materialization
# crashes the body walk". Neither reproduces: every shape below lowers and
# round-trips with the guard removed and nothing else changed.
#
# THE BOUNDS MUST BE UNFOLDABLE, or perl computes the range before B::SoN sees
# it and the test proves nothing. @ARGV and @_ are what force that.
#
# THE ELEMENTS ARE THE CHECK, not the count: a loop starting at the wrong
# value still runs the right number of times.
subtest 'a runtime low bound' => sub {
    round_trips(<<'SRC', 'both bounds runtime');
my $lo = @ARGV ? 9 : 2;
my $hi = $lo + 3;
my @v;
for my $i ($lo..$hi) { push @v, $i }
print "@v\n";
SRC

    round_trips(<<'SRC', 'bounds from @_');
sub f {
    my ($a, $b) = @_;
    my @v;
    for my $i ($a..$b) { push @v, $i }
    return "@v";
}
print f(3, 6), "\n";
SRC

    round_trips(<<'SRC', 'a computed low from $#a');
my @a = (1, 2, 3, 4);
my @v;
for my $i ($#a - 2 .. $#a) { push @v, $i }
print "@v\n";
SRC
};

# THE EMPTY AND SINGLE-ELEMENT RANGES are where an off-by-one hides: `5..2`
# runs zero times and `2..2` runs once, and a loop that ran the wrong number
# still prints something.
subtest 'the degenerate ranges' => sub {
    round_trips(<<'SRC', 'low above high runs zero times');
my $lo = @ARGV ? 1 : 5;
my $hi = 2;
my $n = 0;
for my $i ($lo..$hi) { $n = $n + 1 }
print "n=$n\n";
SRC

    round_trips(<<'SRC', 'low equal to high runs once');
my $lo = @ARGV ? 9 : 2;
my @v;
for my $i ($lo..$lo) { push @v, $i }
print "n=", scalar(@v), " [@v]\n";
SRC
};

# A CONSTANT LOW MUST NOT REGRESS -- it is the shape that already worked, and
# it folds `high+1` at compile time where a runtime high emits an Add.
subtest 'a constant low still lowers' => sub {
    round_trips(<<'SRC', 'a literal range');
my @v;
for my $i (2..5) { push @v, $i }
print "@v\n";
SRC

    round_trips(<<'SRC', 'a constant low with a runtime high');
my @a = (7, 8, 9);
my @v;
for my $i (1..$#a) { push @v, $a[$i] }
print "@v\n";
SRC
};

# AN ACCUMULATOR IS THE CASE THE OLD GUARD WAS REALLY COVERING. `push @v, $i`
# does not read the induction variable arithmetically; `$s = $s + $i` does, and
# then the back-edge is `Add(accumulator_Phi/Int, induction_Phi/Unknown)` --
# which _patch_loop_phi refuses as a lost stamp.
#
# THE INDUCTION VARIABLE IS ALWAYS Int, whatever the bounds are. perl's range
# operator truncates: measured, `2.7..5.2` yields `2 3 4 5`. So this is a fact
# the lowering can assert rather than something to infer from the bounds --
# which is just as well, because `my ($lo,$hi) = @_` leaves `$lo` Unknown while
# `$hi` picks up Num only from its use in `Add($hi, 1)`.
subtest 'an accumulator over a runtime range' => sub {
    round_trips(<<'SRC', 'a numeric accumulator');
sub f {
    my ($lo, $hi) = @_;
    my $s = 0;
    for my $i ($lo..$hi) { $s = $s + $i }
    return $s;
}
print f(1, 4), "\n";
SRC

    round_trips(<<'SRC', 'and one over a constant range still works');
my $s = 0;
for my $i (1..4) { $s = $s + $i }
print "$s\n";
SRC
};

done_testing;
