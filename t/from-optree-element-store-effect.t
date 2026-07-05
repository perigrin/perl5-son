# ABOUTME: Tests element stores materialize -- a threaded store Assign + real Subscript reads.
# ABOUTME: The read-back cache is gone: a read is always a Subscript load, so stores persist to memory.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# `$a[0] = 42` is a bounds-checked element STORE (a side effect). It is threaded
# onto the control chain (like a void call) so it is ordered and reachable. A
# read `$a[0]` is ALWAYS a real Subscript load (no compile-time read-back
# shortcut), so the store's effect reaches memory and the load sees it -- correct
# under aliasing and cross-index, which a value-substitution cache cannot be.

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

subtest 'an element store is a control-threaded, reachable Assign (R6)' => sub {
    my $g = graph_of('sub { my @a = (1, 2, 3); $a[0] = 42; $a[0] }');
    my ($assign) = nodes_of($g, 'Assign');
    ok(defined $assign, 'the element-store Assign is reachable from the graph')
        or return;
    ok($assign->is_stmt_effect, 'the Assign is marked is_stmt_effect');
    is($assign->inputs->[1]->operation, 'Subscript', 'input[1] is the Subscript lvalue');
    is($assign->inputs->[2]->operation, 'Constant', 'input[2] is the stored value');
};

subtest 'a read is a real Subscript, not a cached value (no read-back shortcut)' => sub {
    # `$a[0] = 42; $a[0]` -- the read must be a Subscript LOAD, not the store
    # value substituted in. There is a Subscript for the lvalue AND one for the
    # read (two Subscripts), and the Return yields the read Subscript.
    my $g = graph_of('sub { my @a = (1, 2, 3); $a[0] = 42; $a[0] }');
    my @subs = nodes_of($g, 'Subscript');
    ok(@subs >= 2, 'a read Subscript is emitted (not folded to the stored value)')
        or diag('Subscript count: ' . scalar @subs);
    my ($ret) = nodes_of($g, 'Return');
    is($ret->inputs->[-1]->operation, 'Subscript',
        'the Return value is the read Subscript, not the store value');
};

subtest 'a hash element store is likewise a reachable, threaded Assign (R7)' => sub {
    my $g = graph_of('sub { my %h = (a => 1); $h{a} = 0; $h{a} }');
    my ($assign) = nodes_of($g, 'Assign');
    ok(defined $assign, 'the hash element-store Assign is reachable') or return;
    ok($assign->is_stmt_effect, 'marked is_stmt_effect');
};

subtest 'a plain pad rebind is NOT a stmt-effect Assign (teeth)' => sub {
    # `$x = 2` (pad rebind) propagates via the scope binding -- it must NOT be a
    # control-threaded element store.
    my $g = graph_of('sub { my $x = 1; $x = 2; $x }');
    my ($assign) = nodes_of($g, 'Assign');
    ok(!defined $assign || !$assign->is_stmt_effect,
        'a scalar pad rebind is not a stmt-effect Assign');
};

done_testing();
