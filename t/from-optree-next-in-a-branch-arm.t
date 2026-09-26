# ABOUTME: A `next` inside a branch arm rejoins the header, so the arm simply
# ABOUTME: ends -- unlike `last`, it records no exit edge.
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

# A `next` RECORDS NOTHING, which is what separates it from `last`. The
# unconditional mid-body handler already says so:
#
#     "The back-edge already carries the rejoin, so there is nothing to
#      record: a `next` returns to the header exactly as falling off the end
#      of the body does."
#
# So inside a branch arm a `next` needs no @break_projs entry and no exit
# Region predecessor -- the arm just ends, and the walk stops. That is why this
# is a signal rather than new machinery, unlike the `last` case which needed
# @break_projs threaded through every walker.
#
# Reaching this shape needs a `next` AFTER something that delegates the rest of
# the body to an arm walk -- measured, a preceding guarded loop control does
# it, which is why `next if A; next if B` is the minimal case rather than a
# single guarded next (that one is handled mid-body and always worked).

# ATTEMPTED AND REVERTED 2026-09-26. A 'nexted' signal alone is NOT ENOUGH,
# and the reason is worth keeping because the signal reasoning above is right
# as far as it goes.
#
# Adding `return ($op, 'nexted')` beside the existing 'broke' return, plus a
# consumer in the statement-modifier handler that drops the arm without
# recording anything, made all three cases TRANSLATE -- and the SECOND guard
# then vanished from the graph. Measured on the first case:
#
#     perl 15   (i==2 and i==4 both skipped)
#     emitted 19 (only i==2 skipped)
#
# with the emission holding ONE If where the source has two. So the arm ends
# correctly and the FALL-THROUGH loses the rest of the body: whatever consumed
# the first guard's rest-arm did not carry the second guard into it.
#
# That is a silent wrong answer, which this project's contract ranks below the
# refusal, so the refusal stands. The missing piece is not the signal but
# whatever the rest-arm walk does with a SECOND loop control after the first
# has already ended an arm -- the same delegation the refusal's own comment
# describes ("the `next` arm delegates THE REST OF THE BODY to this walk").
{
    my $todo = todo 'a nexted signal alone loses the second guard; the rest-arm walk needs it too';
round_trips( <<'SRC', 'two guarded nexts in a row' );
my $s = 0;
for my $i (1 .. 6) {
    next if $i == 2;
    next if $i == 4;
    $s += $i;
}
print "$s\n";
SRC

round_trips( <<'SRC', 'a next after a guarded next, in a while loop' );
my $s = 0;
my $i = 0;
while ($i < 6) {
    $i++;
    next if $i == 2;
    next if $i == 4;
    $s += $i;
}
print "$s\n";
SRC

round_trips( <<'SRC', 'a next in a block arm, not a statement modifier' );
my $s = 0;
for my $i (1 .. 5) {
    next if $i == 2;
    if ($i == 3) { next }
    $s += $i;
}
print "$s\n";
SRC

}

# AND `last` AFTER A `next` MUST STILL WORK -- it took its own fix and shares
# this code path, so it is the regression guard. NOT todo'd: it passes today.
round_trips( <<'SRC', 'a last after a next is undisturbed' );
my $s = 0;
for my $i (1 .. 9) {
    next if $i == 2;
    last if $i == 4;
    $s += $i;
}
print "$s\n";
SRC

done_testing;
