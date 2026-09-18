# ABOUTME: a loop exit-Region predecessor from inside the loop is a break.
# ABOUTME: rendered as an inlined arm it ran the continuation twice.
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
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>$dir/err);
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

# THE DEFECT. The producer builds a mid-body `last` correctly: its guard's
# Proj becomes an extra predecessor of the loop's exit Region. Measured on
# `while ($i<5) { $i++; last if $i==4; $s += $i }`:
#
#     Region 17 preds: [8, 16]
#       Proj 8  index 1  <- Loop(3)    the header-false exit
#       Proj 16 index 0  <- If(15)     the break
#
# The deparser had no rule for that second predecessor. It rendered the break
# arm INLINE inside the loop body and then emitted the continuation again at
# the exit, so the program both broke and ran to completion:
#
#     perl 6, emitted 615
#
# THE DISCRIMINATOR IS DOMINANCE, which is how every structured-output
# compiler recovers a break (Relooper, Stackifier): a forward edge whose
# source is INSIDE the loop and whose target is outside. Here that reads
# directly off the graph -- the header-false Proj's source IS the Loop, and
# the break Proj's source is an If the Loop dominates. No IR marker is needed,
# and none was added.
round_trips( <<'SRC', 'a while with a mid-body last' );
my $s = 0; my $i = 0;
while ($i < 5) { $i++; last if $i == 4; $s += $i }
print "$s\n";
SRC

# THE FOREACH FORM IS A SEPARATE, PRODUCER-SIDE DEFECT and is TODO rather than
# fixed here. Measured, the break never reaches the graph at all -- there is no
# `If` in it and the comparison has no consumer:
#
#     for my $i (1..5) { last if $i == 4; $s += $i }
#       Ifs:     []
#       NumEq:   (19, [14, 18])   <- no consumer
#
# The while form builds it correctly (Region 17 takes Proj 8 and Proj 16), so
# this is the foreach walker not reaching the `and` guard handler, not a
# deparser question. Nothing this file fixes can reach it.
round_trips( <<'SRC', 'a foreach with a mid-body last' );
my $s = 0;
for my $i (1..5) { last if $i == 4; $s += $i }
print "$s\n";
SRC

round_trips( <<'SRC', 'an array foreach with a mid-body last' );
my @a = (1,2,3,4,5); my $s = 0;
for my $x (@a) { last if $x == 4; $s += $x }
print "$s\n";
SRC

round_trips( <<'SRC', 'work after a foreach last does not run on the exit pass' );
my @o;
for my $i (1..5) { push @o, "a$i"; last if $i == 3; push @o, "b$i" }
print join(",", @o), "\n";
SRC

# THE BREAK RUNS BEFORE THE REST OF THE BODY, so work after it must not happen
# on the breaking iteration -- the case an inlined arm gets wrong in the other
# direction.
round_trips( <<'SRC', 'work after the last does not run on the exit pass' );
my @o; my $i = 0;
while ($i < 9) { $i++; push @o, "a$i"; last if $i == 3; push @o, "b$i" }
print join(",", @o), "\n";
SRC

# A NEXT IS NOT A BREAK. It rejoins the header rather than leaving, so it must
# keep rendering as a guard on the remainder -- the guard against fixing one
# loop control by breaking the other.
round_trips( <<'SRC', 'a next still guards the remainder' );
my $s = 0;
for my $i (1..5) { next if $i == 2; $s += $i }
print "$s\n";
SRC

# BOTH IN ONE LOOP is also producer-side, and fails in the `while` form too:
# the `last` is absent from the emitted code entirely once a `next` precedes
# it (and `my $phi27 = $phi4;` is emitted before $phi4 is declared). Same
# family as the foreach case -- the graph never carries the break.
# A `last` AFTER A `next` IS REFUSED, NOT DROPPED. The `next` guard walks the
# rest of the body with _walk_branch, which has no guarded-loop-control
# handler -- the `last` hangs off an `and`'s ->other branch that _walk_branch
# never follows, so it was neither lowered nor refused. Measured before:
#
#     for my $i (1..9) { next if $i==2; last if $i==4; $s += $i }
#       perl 4, emitted 43     -- the loop ran to completion
#
# and only ONE If was built (for the next), with the last contributing
# nothing. A silent wrong answer, which the contract ranks below a refusal, so
# it refuses until the rest-arm walk can carry an exit edge.
subtest 'a last after a next is refused, not silently dropped' => sub {
    my ( $data, $err ) = graph_of( <<'SRC' );
my $s = 0;
for my $i (1..9) { next if $i == 2; last if $i == 4; $s += $i }
print "$s
";
SRC
    like $err, qr/GAP:/, 'it is refused';
    like $err, qr/last|loop control/i, '... naming the construct';
};

subtest 'a last after a next in a while is refused too' => sub {
    my ( $data, $err ) = graph_of( <<'SRC' );
my $s = 0; my $i = 0;
while ($i < 9) { $i++; next if $i == 2; last if $i == 4; $s += $i }
print "$s
";
SRC
    like $err, qr/GAP:/, 'it is refused';
};

# A LOOP WITH NO BREAK IS UNCHANGED -- the plain shape, kept so the fix cannot
# regress the common case.
round_trips( <<'SRC', 'a plain loop is unchanged' );
my $s = 0;
for my $i (1..5) { $s += $i }
print "$s\n";
SRC

# A `last` INSIDE AN `if` BLOCK is the ordinary early-exit search, and it
# reached the wrong handler entirely. A block arm opens with a PROLOGUE:
#
#     last if C          other-> last
#     if (C) { last }    other-> enter -> nextstate -> last -> leave
#
# and _is_loop_control_or_exit bounds its scan at `nextstate` -- correct in
# the middle of an arm, wrong at its head. It hit the prologue's nextstate and
# returned 0 before reaching the `last`, so the GUARDED-STATEMENT handler
# claimed the construct and merged a break as though it were a statement.
# Measured, the loop then ran to completion with no `last` emitted at all.
#
# A dead slot at the break lowers; the live case is the multi-exit merge and
# refuses below.
round_trips( <<'SRC', 'a last inside an if block' );
my @o = ("A", "HIT", "C");
foreach (@o) { if ($_ eq "HIT") { last } print "$_\n" }
SRC

# THE FOREACH WALKERS NEVER RAN THE SOUNDNESS PASS. Phase 5's exit-Phi
# construction lived inside _translate_while_loop only, so a slot live at the
# break refused loudly in a `while` and SILENTLY EMITTED A WRONG VALUE in the
# identical foreach:
#
#     foreach (@o) { $n++; if (COND) { last } }
#       perl 2, emitted 1
#
# Lifted into _bind_break_exit_phis and run by all three walkers.
#
# THIS SUBTEST ONCE ASSERTED A REFUSAL, which was the best answer available
# when the producer built the exit Phi and the deparser could not render one.
# It can now: the exit Phi reads as the LOOP VARIABLE (its input 0 IS the
# header Phi), so the break pays that variable its value before leaving. The
# assertion is replaced by the round trip it should always have been --
# t/deparse-loop-exit-phi.t covers the rendering in detail.
round_trips( <<'SRC', 'a live slot at a foreach break round-trips' );
my @o = ("A", "HIT", "C");
my $n = 0;
foreach (@o) { $n++; if ($_ eq "HIT") { last } }
print "$n\n";
SRC

done_testing;
