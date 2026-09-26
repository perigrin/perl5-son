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

# ATTEMPTED AND REVERTED 2026-09-26. The DIAGNOSIS is complete and confirmed;
# only the mechanical refactor it needs is not done.
#
# THE CAUSE: the loop-body walker's generic refusal keys on OpMap's BRANCH flag
# -- `range => [0, undef, 1, BRANCH]` -- and its comment justifies itself for a
# nested loop or if/else, which "minted Projs on the OUTER Loop and truncated
# the walk". A range does neither. It produces a LIST and touches the loop's
# control flow not at all, which is the same property the body walker already
# relies on to delegate `cond_expr` and `entertry`.
#
# So the refusal measures the OP TABLE where it means to measure the CONSTRUCT.
#
# WHAT BLOCKS THE FIX: the range handler is INLINE in the main walk (around
# FromOptree.pm:1127) and `_step` -- the shared dispatcher the body walker can
# reach -- does not have it. Delegating via `_step` was tried and returns
# unhandled, measured. So the handler must be EXTRACTED to a shared sub called
# from both walkers, which is the right design and is a ~70-line move inside a
# 12,000-line file with deep nesting. Three scripted attempts left unbalanced
# braces; it wants a careful manual edit rather than another pattern
# substitution.
#
# Recorded rather than half-done: an extraction that compiles but shifts a
# brace is exactly the kind of change that passes a syntax check and breaks
# something unrelated.
{
    my $todo = todo 'the range handler is inline in the main walk and must be extracted to be shared';
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
