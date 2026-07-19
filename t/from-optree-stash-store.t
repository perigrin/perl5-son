# ABOUTME: Tests a package-scalar store (our $g = 5) emits a control-threaded StashAccess-lvalue Assign.
# ABOUTME: Without the store the graph silently drops `our $g = 5`, so a later `$g` read loads an uninitialized slot.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;
use SoN::FromOptree::EffectMeta;

# `our $g = 5` is a package/global scalar STORE (a side effect). The lvalue is a
# StashAccess node; the store must be an explicit Assign(StashAccess, value)
# threaded onto the control chain (is_stmt_effect), exactly like an element or
# field store. Without it the store falls through the sassign catch-all and is
# DROPPED -- a later `$g` read then loads an uninitialized slot (a miscompile).

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub nodes_of ($g, $op) {
    return grep { $_->operation eq $op } $g->nodes->@*;
}

subtest 'a package-scalar store is a control-threaded, reachable Assign' => sub {
    my $g = graph_of('sub { our $g = 5; $g }');
    my ($assign) = nodes_of($g, 'Assign');
    ok(defined $assign, 'the package-scalar-store Assign is reachable from the graph')
        or return;
    ok(SoN::FromOptree::EffectMeta::is_stmt_effect($assign),
        'the Assign is marked is_stmt_effect');
    is($assign->inputs->[1]->operation, 'StashAccess', 'input[1] is the StashAccess lvalue');
    is($assign->inputs->[2]->operation, 'Constant', 'input[2] is the stored value');
    is($assign->inputs->[2]->value, 5, 'the stored value is 5');
};

subtest 'the stored StashAccess lvalue carries an Int stamp for the read' => sub {
    my $g = graph_of('sub { our $g = 5; $g }');
    my ($sa) = nodes_of($g, 'StashAccess');
    ok(defined $sa, 'a StashAccess node exists') or return;
    is($sa->stash_name, 'main', 'stash is main');
    is($sa->var_name, 'g', 'var is g');
    ok(defined $sa->stamp, 'the StashAccess is stamped (so the read has a repr)')
        or return;
    is($sa->stamp->type, 'Int', 'the stamp is Int');
};

subtest 'the Return yields the StashAccess read after the store' => sub {
    # The store's Assign is the Return's control predecessor, so the read is
    # ordered after the store.
    my $g = graph_of('sub { our $g = 5; $g }');
    my ($ret) = nodes_of($g, 'Return');
    is($ret->inputs->[-1]->operation, 'StashAccess',
        'the Return value is the StashAccess read');
};

done_testing();
