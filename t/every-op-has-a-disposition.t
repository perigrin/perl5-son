# ABOUTME: Every op perl can emit must have a DELIBERATE disposition -- a node,
# ABOUTME: a skip, a control handler, an explicit case, or a declared GAP.
use v5.42.0;
use Test2::V0;

use Opcode ();
use SoN::FromOptree::OpMap;

# WHY THIS EXISTS. An op with no disposition does not fail -- it FALLS THROUGH.
# The walk continues with a stack that may or may not be right, and the damage
# surfaces somewhere else entirely, or not at all.
#
# `eval BLOCK` is the worked example. entertry had no handler, so the walk
# stepped over the body and leavetry popped a value nobody pushed: "Stack
# underflow at StackSim.pm line 25", pointing at the simulator rather than the
# unhandled construct. Every form of block eval had been crashing for months
# and no test noticed, because nothing asserted that entertry was DEALT WITH.
#
# The five legitimate dispositions:
#
#   node        OpMap maps it to an IR node type
#   SKIP        structural, correctly builds nothing (nextstate, lineseq)
#   BRANCH/LOOP the caller's control switch owns it
#   handler     an explicit `$name eq '...'` case in FromOptree
#   GAP         refused by name, with a reason
#
# Anything in NONE of those is a silent hole. This test enumerates perl's own
# op list, so a new op in a new perl release shows up here rather than as an
# unexplained GAP months later. (Measured: 5.38->5.44 added 8 ops and removed
# none -- classname, allstart, anystart, anywhile, substr_left, multiparam,
# paramstore, paramtest. The last three are 5.44's and are unknown here today.)

# Ops CONSUMED BY ANOTHER OP'S HANDLER. Each is the tail of a construct whose
# opener is handled and which skips forward past this op, so it is never
# dispatched on its own. Verified by translating the construct: method dispatch,
# block eval and string eval all produce graphs.
#
# This list is deliberately explicit rather than inferred. `leavetry` sat in
# exactly this category BY ASSUMPTION while its opener had no handler at all --
# that assumption is what hid the block eval crash. Anything added here needs
# the same check: translate the construct and confirm it works.
my %CONSUMED_BY_OPENER = map { $_ => 1 } qw(
    leaveeval leavetry leavegiven leavewhen
    method method_redir method_redir_super method_super
);

# Ops with no disposition and no construct that reaches them yet. Listing them
# is the point: each is a KNOWN hole, not an oversight, and the list should
# shrink. A new op appearing here is a new hole and fails the test below.
my %UNREACHED = map { $_ => 1 } qw(
    break cmpchain_dup dump pushdefer
);

sub dispositions () {
    my $m   = SoN::FromOptree::OpMap->new;
    my $src = do {
        open my $fh, '<', 'lib/SoN/FromOptree.pm' or die "open FromOptree: $!";
        local $/; <$fh>;
    };
    my %gap = map { $_ => 1 } ($src =~ /^\s+(\w+)\s+=> "GAP:/gm);

    my (%how, @undecided);
    for my $op (sort +Opcode::opset_to_ops(Opcode::full_opset())) {
        my $d = defined $m->node_type($op)              ? 'node'
              : $m->is_skip($op)                        ? 'skip'
              : ($m->is_branch($op) || $m->is_loop($op)) ? 'control'
              : $gap{$op}                                ? 'gap'
              : $src =~ /name eq \x27\Q$op\E\x27/        ? 'handler'
              : $CONSUMED_BY_OPENER{$op}                 ? 'consumed'
              : $UNREACHED{$op}                          ? 'unreached'
              :                                            undef;
        defined $d ? $how{$d}++ : push @undecided, $op;
    }
    return (\%how, \@undecided);
}

subtest 'every op perl can emit has a deliberate disposition' => sub {
    my ($how, $undecided) = dispositions();

    diag(sprintf "  %-10s %3d", $_, $how->{$_})
        for sort { $how->{$b} <=> $how->{$a} } keys %$how;

    diag("  UNDECIDED: $_") for @$undecided;
    is($undecided, [],
        'no op falls through with no node, no handler, and no GAP');
};

# THE ALLOWLISTS MUST STAY HONEST. An op listed as consumed-by-opener or
# unreached that LATER gets a real disposition should be removed from the list,
# or the list slowly becomes a place where holes hide.
subtest 'the allowlists contain only ops that need to be there' => sub {
    my $m   = SoN::FromOptree::OpMap->new;
    my $src = do {
        open my $fh, '<', 'lib/SoN/FromOptree.pm' or die "open FromOptree: $!";
        local $/; <$fh>;
    };
    my %gap = map { $_ => 1 } ($src =~ /^\s+(\w+)\s+=> "GAP:/gm);

    my @stale;
    for my $op (sort keys %CONSUMED_BY_OPENER, keys %UNREACHED) {
        push @stale, $op
            if defined $m->node_type($op) || $m->is_skip($op)
            || $m->is_branch($op) || $m->is_loop($op) || $gap{$op}
            || $src =~ /name eq \x27\Q$op\E\x27/;
    }
    diag("  now has a real disposition, drop from the allowlist: $_")
        for @stale;
    is(\@stale, [], 'no allowlisted op has quietly gained a real disposition');
};

done_testing;
