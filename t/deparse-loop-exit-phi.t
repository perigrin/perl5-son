# ABOUTME: a slot live at a loop break needs its value from whichever exit ran.
# ABOUTME: the exit Phi is a merge the loop emitter must place, not inline.
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

# THE MULTI-EXIT VALUE MERGE. A loop with a mid-body `last` has TWO exits, and
# a slot whose value differs between them needs a Phi at the join. The
# producer builds one -- _bind_break_exit_phis, over
# [header-Phi, break-binding], regioned on the loop's exit Region -- and the
# deparser refused it: a Phi whose region is a plain Region is normally a
# diamond join, inlined at the join rather than named, so reading this one
# found no variable ("a Phi whose region is a `Region` rather than a Loop").
#
# Measured on `foreach (@o) { $n++; if (COND) { last } }`:
#
#     20 Phi in=[4, 6] rgn=19        4 = header Phi, 6 = the incremented $n
#     19 Region in=[7, 18]           7 = header-false exit, 18 = the break
#
# INPUTS PAIR WITH THE REGION'S PREDECESSORS POSITIONALLY (SoN::IR::Node::Phi:
# "inputs[i] pairs with predecessors[i]"), so input 0 is the value on the
# header-false path and input 1 the value at the break.
round_trips( <<'SRC', 'a counter live at the break' );
my @o = ("A", "HIT", "C");
my $n = 0;
foreach (@o) { $n++; if ($_ eq "HIT") { last } }
print "$n\n";
SRC

# A STATEMENT BEFORE THE `last` IN THE BLOCK is a different construct and
# still refuses: _guarded_loop_control looks at the arm's FIRST real op, which
# here is the assignment, so this is a multi-statement arm rather than a
# guarded control transfer. It reaches the arm walk, which carries no exit
# edge -- an honest refusal, and separate work from the exit Phi.
{
    my $todo = todo 'a multi-statement arm ending in `last` needs the arm-walk exit edge';
    round_trips( <<'SRC', 'a flag set before the break' );
my @o = ("A", "HIT", "C");
my $found = 0;
foreach (@o) { if ($_ eq "HIT") { $found = 1; last } }
print "$found\n";
SRC
}

# THE LOOP THAT NEVER BREAKS takes the header-false arm, so the exit value is
# the header Phi -- the case a fix keyed only on the break arm would get wrong.
round_trips( <<'SRC', 'a loop whose break never fires' );
my @o = ("A", "B", "C");
my $n = 0;
foreach (@o) { $n++; if ($_ eq "MISSING") { last } }
print "$n\n";
SRC

# THE while FORM has the same shape and refused for the same reason.
round_trips( <<'SRC', 'a while with a live slot at the break' );
my $n = 0; my $i = 0;
while ($i < 5) { $i++; $n++; last if $i == 3 }
print "$n\n";
SRC

# A DEAD SLOT IS UNCHANGED: nothing reads it after the loop, so DCE drops the
# exit Phi and the loop renders as it did before.
round_trips( <<'SRC', 'a dead slot at the break still lowers' );
my @o = ("A", "HIT", "C");
foreach (@o) { if ($_ eq "HIT") { last } print "$_\n" }
SRC

done_testing;
