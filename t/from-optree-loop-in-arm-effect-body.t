# ABOUTME: a loop in a branch arm whose body advances control, not just values.
# ABOUTME: leaveloop reached _step and popped 2 operands nothing had pushed.
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
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f;
    return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ( $data && $data->{methods}{'main::__PROGRAM__'} ) {
        fail "$name: translates";
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

# THE DEFECT, AND WHY IT HID. t/from-optree-loop-in-arm.t already pins that a
# foreach in an arm translates -- but its body is `$n = $n + $i`, which LEAVES
# A VALUE ON THE STACK. The refusal guarding this is `leaveloop` with
# stack_depth < 2, so a body that leaves residue satisfies it by accident.
#
# Measured, the body is walked three times and only the residue differs:
#
#     $s += $x      leaves 1 per walk   ->  depth 3 at leaveloop   passes
#     print "x"     leaves 0 per walk   ->  depth 1 at leaveloop   GAP
#
# and the prediction holds both ways: `print; $s += $x` passes while
# `print; print` fails. The guard was measuring leftover operands from
# repeated body walks, which says nothing about whether the loop translated.
#
# ROOT CAUSE: OpMap declares `leaveloop => [2, ...]` -- pop two. At top level
# `leaveloop` never reaches _step (the main walk handles it directly and steps
# past), so the pop never happens. Inside a branch arm there was no such
# handler, so it fell through to _step and popped two operands nothing had
# pushed -- "Stack underflow", which the GAP was added to convert into an
# honest refusal. The guard was right; the pop was wrong.
round_trips( <<'SRC', 'a loop in an arm whose body prints' );
my $c = 1;
if ($c) { for my $x (1, 2) { print "x$x\n" } }
SRC

# TWO EFFECTS, NO RESIDUE AT ALL -- the shape that fails even when a single
# effect might leave something behind.
round_trips( <<'SRC', 'a loop in an arm with two effect statements' );
my $c = 1;
if ($c) { for my $x (1, 2) { print "a$x\n"; print "b$x\n" } }
SRC

# THE ARM IS STILL AN ARM. The loop must not swallow what follows it inside
# the branch, nor what follows the branch.
round_trips( <<'SRC', 'statements after the loop and after the branch' );
my $c = 1;
if ($c) { for my $x (1, 2) { print "x$x\n" } print "after-loop\n" }
print "after-if\n";
SRC

# THE ELSE ARM TOO, and the not-taken path must not run.
round_trips( <<'SRC', 'a loop in an else arm' );
my $c = 0;
if ($c) { print "taken\n" } else { for my $x (1, 2) { print "e$x\n" } }
SRC

# THE CORPUS SHAPE that comp/utf.t refused on: a statement-modifier `next`
# whose not-taken path holds the loop.
round_trips( <<'SRC', 'a loop after a next-if inside a loop' );
for my $e (1, 2) {
    next if $e == 1;
    for my $x (1, 2) { print "x$x\n" }
}
SRC

# AND THE VALUE-BODY FORM IS UNDISTURBED -- the shape the existing test pins,
# kept here so a fix cannot trade one for the other.
round_trips( <<'SRC', 'a loop in an arm whose body accumulates' );
my $c = 1; my $s = 0;
if ($c) { for my $x (1, 2) { $s += $x } }
print "$s\n";
SRC

done_testing;
