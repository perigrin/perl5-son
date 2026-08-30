# ABOUTME: A comparison is never a compound assignment -- OPf_MOD on its first
# ABOUTME: operand must not rebind the variable to the comparison's result.
use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub ops_of ($g, $op) { return grep { $_->operation eq $op } $g->nodes->@* }

# THE MISCOMPILE. The compound-assignment detector recognises `$x += 2` by three
# facts: the first input is a PadAccess, the first op is a padsv, and that padsv
# carries OPf_MOD. Then it REBINDS the variable to the operator's result, which
# is what `+=` means.
#
# perl leaves OPf_MOD set on a COMPARISON's first operand after folding a dead
# branch arm -- `if (0) {...} elsif ($x != $y)` compiles the first operand as
# `padsv sM`. All three facts matched, so `!=` was taken for a read-modify-write
# and $x was rebound to the Boolean. There is no `$x !=` operator; a comparison
# reads its operands and yields a Boolean, never a new value for either.
#
# Inside a loop the damage is silent and arithmetic: the body's `$i + 1` read
# the comparison instead of the counter.
#
#     Add(NumNe, 1)   <- what Print consumed
#     Add(Phi,   1)   <- the counter, correct
#
# `for my $i (0..2) { ...; print $i + 1 }` printed 111 where perl prints 123.
# Found in perl's own t/base/translate.t.
subtest 'a comparison does not rebind its operand' => sub {
    my $g = graph_of(
        'sub { for my $i (0..2) { if (0) { print "n" }'
      . ' elsif (utf8::unicode_to_native(utf8::native_to_unicode($i)) != $i) { print "n" }'
      . ' print $i + 1; } }');
    ok($g, 'the graph exists') or return;

    my ($cmp) = ops_of($g, 'NumNe');
    ok($cmp, 'the comparison exists') or return;

    # THE ASSERTION. No Add may take the comparison as an operand: `$i + 1`
    # adds to the COUNTER. An Add over a Boolean is the miscompile.
    my @bad = grep {
        my $a = $_;
        grep { defined $_ && $_->id eq $cmp->id } $a->inputs->@*
    } ops_of($g, 'Add');
    is(scalar(@bad), 0, 'no Add consumes the comparison result');
};

# THE COUNTER MUST REACH THE ADD. The negative above would also pass if the Add
# vanished, so assert the positive: an Add reads the loop's Phi.
subtest 'the body add reads the induction variable' => sub {
    my $g = graph_of(
        'sub { for my $i (0..2) { if (0) { print "n" }'
      . ' elsif (utf8::unicode_to_native(utf8::native_to_unicode($i)) != $i) { print "n" }'
      . ' print $i + 1; } }');
    my @phis = ops_of($g, 'Phi');
    ok(scalar(@phis), 'the induction Phi exists') or return;
    my %phi = map { $_->id => 1 } @phis;
    my $ok = grep {
        grep { defined $_ && $phi{ $_->id } } $_->inputs->@*
    } ops_of($g, 'Add');
    ok($ok, 'an Add reads the induction Phi');
};

# THE SECOND HALF OF THE SAME FLAG BUG. Treating the OPf_MOD comparison operand
# as an assignment TARGET also pushed a fresh unbound PadAccess in place of the
# slot's live binding -- so the comparison read a node nothing defines while the
# real value sat in the header Phi. Two nodes for one variable.
#
# Here perl has folded the round trip to the identity, so the elsif really is
# `$i != $i` and BOTH operands must be the same node. If either is a bare
# PadAccess the test is no longer provably false and the arm could fire.
subtest 'both operands of the folded self-comparison are the same node' => sub {
    my $g = graph_of(
        'sub { for my $i (0..2) { if (0) { print "n" }'
      . ' elsif (utf8::unicode_to_native(utf8::native_to_unicode($i)) != $i) { print "n" }'
      . ' print $i + 1; } }');
    my ($cmp) = ops_of($g, 'NumNe');
    ok($cmp, 'the comparison exists') or return;
    my ($l, $r) = $cmp->inputs->@*;
    ok($l && $r, 'it has two operands') or return;
    is($l->id, $r->id, 'x != x compares one node with itself');
    is($l->operation, 'Phi',
        'and that node is the induction Phi, not a fresh unbound PadAccess');
};

# COMPOUND ASSIGNMENT STILL WORKS. The fix excludes comparisons only; `+=` is
# the construct this detector exists for and must keep rebinding.
subtest 'a real compound assignment still rebinds' => sub {
    my $g = graph_of('sub { my $x = 1; $x += 2; $x }');
    ok(scalar(ops_of($g, 'Add')), 'the += builds an Add');
    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    ok($ret, 'the sub returns') or return;
    my ($v) = $ret->inputs->@*;
    is($v->operation, 'Add',
        'the returned value is the += result -- the slot was rebound');
};

subtest 'string compound assignment still rebinds' => sub {
    my $g = graph_of('sub { my $s = "a"; $s .= "b"; $s }');
    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    ok($ret, 'the sub returns') or return;
    my ($v) = $ret->inputs->@*;
    is($v->operation, 'Concat', 'the returned value is the .= result');
};

done_testing;
