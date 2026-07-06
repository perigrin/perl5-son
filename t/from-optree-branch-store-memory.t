# ABOUTME: Tests an if-branch element store builds If/Proj/Region + a memory-Phi (memory-SSA 2b-1).
# ABOUTME: The store is control-dependent on Proj(If,true); the post-branch read's memory is a Phi over the Region.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# `if ($c) { $a[0] = 9 } $a[0]` -- the store is CONTROL-DEPENDENT on the branch
# (its control is Proj(If, true)), and the memory after the join is a Phi over the
# Region merging [arm_store_memory, base_memory]. The post-branch read takes that
# memory-Phi. This is the canonical Sea-of-Nodes conditional-store shape (NOT a
# memory value-select TernaryExpr).

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub of_op ($g, $op) { grep { $_->operation eq $op } $g->nodes->@* }

my $SRC = 'sub { my @a = (1,2,3); my $c = 1; if ($c) { $a[0] = 9 } $a[0] }';

subtest 'the if-branch builds an If + Region' => sub {
    my $g = graph_of($SRC);
    my ($if) = of_op($g, 'If');
    ok(defined $if, 'graph has an If node') or return;
    my ($region) = of_op($g, 'Region');
    ok(defined $region, 'graph has a Region (the join)');
};

subtest 'the element store is control-dependent on Proj(If, true)' => sub {
    my $g = graph_of($SRC);
    # the store is the element-store Assign (a Subscript lvalue among its inputs)
    my ($store) = grep {
        grep { ref $_ && $_->operation eq 'Subscript' } $_->inputs->@*
    } of_op($g, 'Assign');
    ok(defined $store, 'has an element-store Assign') or return;
    # an element-store Assign carries control as inputs[0] (is_stmt_effect):
    # inputs => [control, target, value].
    my $ctrl = $store->inputs->[0];
    ok(defined $ctrl, 'the store has a control input') or return;
    is($ctrl->operation, 'Proj', 'store control is a Proj');
    is($ctrl->inputs->[0]->operation, 'If', 'the Proj is off the If');
    is($ctrl->index, 0, 'index 0 = the true arm (store runs when the guard is taken)');
};

subtest 'the post-branch read memory is a Phi over the Region' => sub {
    my $g = graph_of($SRC);
    # the returned read is the LAST-evaluated Subscript feeding the Return
    my ($ret) = of_op($g, 'Return');
    my $read = $ret->inputs->[-1];
    is($read->operation, 'Subscript', 'the return value is a Subscript (the read)') or return;
    my $mem = $read->inputs->[2];
    ok(defined $mem, 'the read has a memory input') or return;
    is($mem->operation, 'Phi', 'the read memory is a Phi (the memory merge)') or return;
    ok(defined $mem->region && $mem->region->operation eq 'Region',
        'the Phi is over the Region');
};

done_testing();
