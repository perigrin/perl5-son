# ABOUTME: A list-context range in a loop body is a VALUE, not loop control, so
# ABOUTME: the loop walker must lower it rather than refuse it as a branch op.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub run_perl ($src) {
    my $f = "$dir/r." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $f 2>&1);
    unlink $f;
    return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
    unlink $f;
    return ( eval { JSON::PP->new->decode($j) }, $e );
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my ( $data, $err ) = graph_of($src);
    unless ( $data && $data->{methods}{'main::__PROGRAM__'} ) {
        fail "$name: translates";
        diag $err;
        return;
    }
    my $d   = SoN::Deparse->new;
    my $out = eval { $d->render($data) };
    unless ( defined $out ) {
        my $g = $d->gap // $@ // '(no reason)';
        $g =~ s/\n.*//s;
        fail "$name: renders";
        diag $g;
        return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# THE CATCH-ALL MEASURED THE OP TABLE, NOT THE CONSTRUCT. OpMap declares
# `range => [0, undef, 1, BRANCH]`, so the loop-body walker's generic refusal --
# "nested control structure in a body is only translated by the MAIN walker" --
# fired on it. That refusal is right about a nested loop or if/else, which mint
# Projs on the outer Loop; it is wrong about a range, which produces a LIST and
# touches the loop's control flow not at all.
#
# A list-context range now lowers to a Range node (see
# t/from-optree-runtime-range.t), and the lowering needs no loop context: it
# walks the two bound arms, builds one node, and pushes a value. Exactly the
# same delegation the body walker already grants `cond_expr` and `entertry`,
# and for the same stated reason -- nothing of it touches the Loop.
#
# THE SCALAR FORM MUST KEEP REFUSING, and it must refuse for its own reason: a
# flip-flop carries state across evaluations, which is genuinely loop-adjacent.

# THE REFUSAL MEASURED THE OP TABLE, NOT THE CONSTRUCT. The loop-body walker's
# generic refusal keys on OpMap's BRANCH flag -- `range => [0, undef, 1,
# BRANCH]` -- and its own justification is about a construct that mints Projs on
# the OUTER Loop. A range does not: it produces a LIST and touches the loop's
# control flow not at all, which is the same property that already lets the body
# walker delegate `cond_expr` and `entertry`.
#
# Fixed by EXTRACTING the range handler from the main walk into a shared sub
# both walkers call, rather than duplicating it. The scalar-context flip-flop
# still refuses, under its own name.
round_trips( <<'SRC', 'a runtime range inside a foreach body' );
my $n = 3;
for my $i (1 .. 2) {
    my @q = (1 .. $n);
    print scalar(@q);
}
print "\n";
SRC

round_trips( <<'SRC', 'a runtime range inside a while body' );
my $n = 3;
my $i = 0;
while ($i < 2) {
    $i++;
    my @q = (1 .. $n);
    print scalar(@q);
}
print "\n";
SRC

# A BOUND THAT VARIES PER ITERATION IS A DEPARSER DEFECT, not a producer one,
# and the graph proves it. For `for my $n (1..3) { my @q = (1..$n) }`:
#
#     8  Phi          in=[7,17]   region=2   the induction variable
#     12 Range        in=[7,8]               reads the Phi -- varies correctly
#
# So the producer says exactly the right thing. The DEPARSER hoists the Range
# above the loop, emitting
#
#     my @q = (((1) .. ($phi16)));     <- before $phi16 is declared
#     my $phi16 = 1;
#     while ((4 > $phi16)) { ... }
#
# which prints `0 0 0` where perl prints `1 2 3`. A pure node placed above a
# variable it reads, which is a scheduling question in the emitter rather than
# anything about ranges.
{
    my $todo = todo 'the deparser hoists a pure Range above the loop Phi it reads';
    round_trips( <<'SRC', 'the range bound varies per iteration' );
my @sizes;
for my $n (1 .. 3) {
    my @q = (1 .. $n);
    push @sizes, scalar(@q);
}
print "@sizes\n";
SRC
}

done_testing;
