# ABOUTME: a package scalar mutated in a loop body carries across iterations --
# ABOUTME: this loop's Phi outranks the demotion, exactly as a foreach alias does.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub write_tmp ($src, $tag) {
    my $f = "$dir/$tag." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    return $f;
}

sub graph_of ($src) {
    my $f = write_tmp( $src, 'g' );
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    return eval { JSON::PP->new->decode($j) };
}

sub emit ($src) {
    my $data = graph_of($src) or return ( undef, 'no graph' );
    return ( undef, 'no program' ) unless $data->{methods}{'main::__PROGRAM__'};
    my $out = eval { SoN::Deparse->new->render($data) };
    return ( undef, ( $@ || 'refused' ) ) unless defined $out;
    return ( $out, undef );
}

sub runs ($src) {
    my $f = write_tmp( $src, 'r' );
    my $o = qx($^X $f 2>&1);
    unlink $f;
    return $o;
}

# A PAD SLOT'S READ RESOLVES THROUGH THE SCOPE BINDING, so re-pointing the slot
# at the loop header Phi (_patch_loop_phi) is enough -- the next read finds the
# Phi. A PACKAGE scalar's read does not: the gvsv handler builds a fresh
# memory-pinned EntryDef whenever the name is in _package_scalars_written(), so
# that a write in another sub is visible. Right for the cross-sub case, wrong
# inside a loop, where the value IS carried and the carrier is the Phi.
#
# The Phi is BUILT -- _scout_mutated_targs detects the stash key and has no
# pad-only filter -- and then nothing reads it. Measured:
#
#     our $n = 5;
#     foreach $t ($n..$n + 3) { print "ok $t\n"; $n++ }
#     print "end $n\n";
#
#     perl   ok 5 / ok 6 / ok 7 / ok 8 / end 9
#     ours   ok 5 / ok 6 / ok 7 / ok 8 / end 6
#
# because the body's increment reads the PRE-LOOP EntryDef, so the store writes
# 6 on every pass. A SILENT WRONG ANSWER, not a refusal -- which is why this is
# recorded as a failing expectation rather than left unmeasured.
#
# FIXED BY THE RULE ALREADY WRITTEN FOR ALIASES. @ALIAS_BOUND_KEYS suspends the
# demotion for a foreach's iterator key because "the loop itself established the
# binding one op ago, in this graph". A loop Phi is the same claim one construct
# over, so @LOOP_PHI_KEYS suspends it for the keys a loop carries, for exactly
# the loop's extent. The doc named the memory Phi as the other candidate owner;
# the value Phi wins because the precedent already chose it.
#
# THREE LOOP BUILDERS, ONE RULE. The while/C-style form, the range foreach and
# the list foreach each build their own %phis, so _carried_stash_keys answers
# the question once and all three call it -- a rule spelled at one site is a
# rule the other two silently lack.
#
# ONLY THE RANGE FOREACH WAS ACTUALLY BROKEN, and both halves of the fix were
# falsified to establish that: disabling _carried_stash_keys, and separately
# disabling the increment handler's Phi read, each break subtest 1 and NOTHING
# ELSE. The while, list-foreach, sequential and `+=` cases below pass at HEAD
# too -- checked by stashing.
#
# They stay as cases rather than being cut. Each is a DIFFERENT write form or
# builder reaching the same rule, so they are what says a later change to that
# rule has not broken the forms it was not aimed at; the falsification above is
# what stops them being mistaken for evidence of this fix.
subtest 'a package scalar mutated in a loop body is loop-carried' => sub {
    subtest 'a counter in a foreach body accumulates' => sub {
        my $src = <<'SRC';
our $n = 5;
foreach $t ($n..$n + 3) {
    print "ok $t # skipped\n";
    $n++;
}
print "end $n\n";
SRC
        my ( $out, $why ) = emit($src);
        ok defined $out, 'renders' or do { diag $why; return };
        is runs($out), runs($src), 'the counter reaches 9'
            or diag $out;
    };

    subtest 'a counter in a while body accumulates' => sub {
        my $src = <<'SRC';
our $n = 0;
my $i = 0;
while ($i < 3) {
    $n++;
    $i++;
}
print "n=$n\n";
SRC
        my ( $out, $why ) = emit($src);
        ok defined $out, 'renders' or do { diag $why; return };
        is runs($out), runs($src), 'the counter reaches 3'
            or diag $out;
    };

    # THE LIST FOREACH IS THE THIRD BUILDER, and it had to be told separately.
    subtest 'a counter in a list-foreach body accumulates' => sub {
        my $src = <<'SRC';
our $n = 0;
foreach my $x ('a', 'b', 'c') {
    $n++;
}
print "n=$n\n";
SRC
        my ( $out, $why ) = emit($src);
        ok defined $out, 'renders' or do { diag $why; return };
        is runs($out), runs($src), 'the counter reaches 3'
            or diag $out;
    };

    # TWO LOOPS OVER ONE KEY, which is what the `local` SCOPING is for. The
    # suspension has to END with the first loop: a read AFTER it must go back to
    # being memory-bound, and the second loop must establish its own carry from
    # wherever the first left the counter.
    #
    # (The nested form is the sharper test of the PUSH, but nested loops are a
    # pre-existing refusal -- `GAP: enterloop inside a loop body not yet
    # lowered`, measured with only lexicals in play -- so it cannot be written
    # here yet.)
    subtest 'two sequential loops over one counter accumulate' => sub {
        my $src = <<'SRC';
our $n = 0;
my $i = 0;
while ($i < 3) {
    $n++;
    $i++;
}
print "mid $n\n";
my $k = 0;
while ($k < 4) {
    $n++;
    $k++;
}
print "end $n\n";
SRC
        my ( $out, $why ) = emit($src);
        ok defined $out, 'renders' or do { diag $why; return };
        is runs($out), runs($src), 'the counter reaches 3 then 7'
            or diag $out;
    };

    # A COMPOUND ASSIGNMENT IS THE OTHER WRITE FORM. The increment handler was
    # one of two places that read the slot; `+=` goes through sassign, so this
    # says the gvsv read learned the rule too.
    subtest 'a compound assignment in a loop body accumulates' => sub {
        my $src = <<'SRC';
our $n = 0;
my $i = 0;
while ($i < 4) {
    $n += 10;
    $i++;
}
print "n=$n\n";
SRC
        my ( $out, $why ) = emit($src);
        ok defined $out, 'renders' or do { diag $why; return };
        is runs($out), runs($src), 'the counter reaches 40'
            or diag $out;
    };
};

# THE PAD FORM IS THE CONTROL, and it must keep working: the same loop over a
# LEXICAL counter is loop-carried correctly today, which is what says the defect
# is about the package read path and not about loops.
subtest 'a lexical counter in a loop body still accumulates' => sub {
    my $src = <<'SRC';
my $n = 0;
my $i = 0;
while ($i < 3) {
    $n++;
    $i++;
}
print "n=$n\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'the lexical counter reaches 3'
        or diag $out;
};

done_testing;
