# ABOUTME: Tests SoN::FromOptree method dispatch (Class->new, $obj->meth).
# ABOUTME: A method call produces Call(dispatch_kind=method, name, class_name for ->new).

use v5.42.0;
use feature 'class';
use Test2::V0;
use B;
no warnings 'experimental::class';

use SoN::OptSuppress;
use SoN::FromOptree;

# `Class->new` and `$obj->meth` are method dispatch: pushmark, invocant,
# method_named[name], entersub. They must produce a Call with
# dispatch_kind='method' and name=<method>; the constructor's class_name is the
# invocant class (a bareword constant). A later `$g->meth` resolves its invocant
# through the scope binding to the Call(new), which the backend reads class_name
# from.

class Greeter {
    method greet { 42 }
}

class Counter {
    field $n :param = 0;
    method inc { $n += 1 }
    method val { return $n }
}

# A method that dispatches on $self: the self-call names the ENCLOSING class
# (from the CV stash), not an external invocant (zhi 019f5dec).
class SelfCaller {
    method flag { 1 }
    method pick { $self->flag() ? 10 : 20 }
}

sub canonical_graph ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub calls_of ($graph) {
    return grep { $_->operation eq 'Call' } $graph->nodes->@*;
}

subtest 'Class->new produces a method-dispatch Call with class_name' => sub {
    my $g = canonical_graph('sub { Greeter->new }');
    my ($call) = calls_of($g);
    ok(defined $call, 'has a Call node');
    is($call->dispatch_kind, 'method', 'dispatch_kind is method');
    is($call->name, 'new', 'method name is new');
    is($call->class_name, 'Greeter', 'class_name is the bareword invocant');
};

subtest '$obj->meth produces a method-dispatch Call named for the method' => sub {
    my $g = canonical_graph('sub { my $g = Greeter->new; $g->greet }');
    my @calls = calls_of($g);
    my ($greet) = grep { $_->name eq 'greet' } @calls;
    ok(defined $greet, 'has a Call(greet)');
    is($greet->dispatch_kind, 'method', 'dispatch_kind is method');
    # The invocant resolves through the scope binding to the Call(new); the
    # greet Call propagates that constructor's class_name (the backend requires
    # class_name ON the method Call node).
    my ($new) = grep { $_->name eq 'new' } @calls;
    is($greet->inputs->[0], $new,
        'the greet invocant is the Call(new) (scope-resolved $g)');
    is($greet->class_name, 'Greeter',
        'greet Call propagates class_name from its constructor invocant');
};

subtest 'a void method call is threaded onto the control chain (obj-state A)' => sub {
    # $c->inc in statement position mutates $c and its result is discarded.
    # It must carry a control edge (input[0] = the prior control node) and be
    # marked a statement effect, so the loader threads it into the effect chain
    # instead of leaving it orphaned (which gets DCE'd, losing the mutation).
    my $g = canonical_graph(
        'sub { my $c = Counter->new(n => 10); $c->inc; $c->val }');
    my ($inc) = grep { $_->operation eq 'Call' && $_->name eq 'inc' }
        $g->nodes->@*;
    ok(defined $inc, 'has a Call(inc)') or return;
    ok(defined $inc->control_in,
        'the void inc is marked a statement effect (control_in set)');
    my $ctrl = $inc->control_in;
    ok(defined $ctrl && $ctrl->operation =~ /^(Start|Call|Region|Proj|If|Loop)$/,
        'inc carries a control_in edge to the prior control');
};

subtest 'a value-context method call is ALSO control-pinned (R1.0 effect-by-default)' => sub {
    # $c->val is in return/value position -- its result is consumed AND
    # pushed as a value, but every Call is control-pinned regardless of void
    # vs. value context (R1.0): the pin keeps it ordered and reachable even
    # if its value later goes unused, and advances the control chain so a
    # FOLLOWING effect does not float ahead of it (F3).
    my $g = canonical_graph(
        'sub { my $c = Counter->new(n => 10); $c->val }');
    my ($val) = grep { $_->operation eq 'Call' && $_->name eq 'val' }
        $g->nodes->@*;
    ok(defined $val, 'has a Call(val)') or return;
    ok(defined $val->control_in,
        'val is control-pinned (control_in set) even though its value is consumed');
    my ($new) = grep { $_->operation eq 'Call' && $_->name eq 'new' }
        $g->nodes->@*;
    is($val->control_in, $new,
        'val->control_in chains to the prior control (the new Call)');
};

subtest 'Class->new(k=>v) splits its kv-list into param_names + value inputs' => sub {
    # Counter->new(n => 10): the constructor arg list is a param=>value kv-list.
    # It must be emitted as Call(name=new, class_name=Counter, param_names=['n'],
    # inputs=[Constant(10)]) -- the bare keys on param_names, the values as
    # inputs (the class rides as class_name, not as an input). The backend's
    # _lower_call_new binds inputs[i] to the field named param_names[i]; a flat
    # kv-list of inputs leaves param_names empty and stores field defaults.
    my $g = canonical_graph('sub { Counter->new(n => 10) }');
    my ($new) = grep { $_->name eq 'new' } calls_of($g);
    ok(defined $new, 'has a Call(new)') or return;
    is($new->class_name, 'Counter', 'class_name is Counter');
    is($new->param_names, ['n'], 'param_names carries the bare key');
    is(scalar($new->inputs->@*), 1, 'one input: the value only (class dropped)');
    is($new->inputs->[0]->value, 10, 'the value input is Constant(10)');
    # A constructor returns the constructed object instance.
    is($new->stamp && $new->stamp->type, 'Object', 'new is stamped Object');
};

subtest 'void-chain Return leads with the return-expression value (R1.0)' => sub {
    # my $c = Counter->new(n=>10); $c->inc; $c->val
    # The trailing statement's VALUE (Call val) is the result: Return.inputs
    # is ALWAYS just [value] (produce-time control, i3). Under R1.0
    # effect-by-default EVERY call is control-pinned, val included, so
    # Return.control_in is now val itself (not inc) -- val's own control_in
    # chains back to inc, which chains back to new, so inc stays reachable
    # transitively rather than being Return's direct control predecessor.
    my $g = canonical_graph(
        'sub { my $c = Counter->new(n => 10); $c->inc; $c->val }');
    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    ok(defined $ret, 'has a Return') or return;
    my ($val) = grep { $_->operation eq 'Call' && $_->name eq 'val' } $g->nodes->@*;
    my ($inc) = grep { $_->operation eq 'Call' && $_->name eq 'inc' } $g->nodes->@*;
    is($ret->inputs->[0], $val,
        'Return.inputs[0] is the val Call (the return-expression value)');
    isnt($ret->inputs->[0], $inc,
        'Return.inputs[0] is NOT the void inc Call');
    is($ret->control_in, $val,
        'Return.control_in is val (every Call is control-pinned under R1.0)');
    is($val->control_in, $inc,
        'val->control_in chains to inc, so inc stays reachable transitively (not dropped)');
};

subtest 'single-statement Return still leads with control (B1 regression)' => sub {
    # my $c = Counter->new(n=>10); $c->val  -- no void effect. Under R1.0
    # val is itself control-pinned (chaining to new, then Start), so
    # Return.control_in is now val (a Call), not a bare CFG node; the value
    # remains the sole Return input. This must NOT change.
    my $g = canonical_graph(
        'sub { my $c = Counter->new(n => 10); $c->val }');
    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    my ($val) = grep { $_->operation eq 'Call' && $_->name eq 'val' } $g->nodes->@*;
    my ($new) = grep { $_->operation eq 'Call' && $_->name eq 'new' } $g->nodes->@*;
    is($ret->inputs->[-1], $val, 'value is the trailing input');
    is($ret->control_in, $val,
        'control (the control-pinned val Call) is carried on control_in');
    is($val->control_in, $new,
        'val->control_in chains to new, and on to Start (the CFG root)');
};

subtest 'a $self-> method call stamps the enclosing class_name (zhi 019f5dec)' => sub {
    my $g = SoN::FromOptree->translate(\&SelfCaller::pick);
    my ($call) = grep { $_->operation eq 'Call' && ($_->name // '') eq 'flag' }
                 $g->nodes->@*;
    ok(defined $call, 'the $self->flag() self-call is a Call node');
    is($call->dispatch_kind, 'method', 'dispatch_kind is method');
    is($call->class_name, 'SelfCaller',
        'class_name is the ENCLOSING class (from the CV stash), not undef');
    # The receiver is the $self PadAccess, Object-stamped (so the backend gives
    # it a repr) with no VarDecl input (so the backend lowers it to %self).
    my ($recv) = grep {
        $_->operation eq 'PadAccess' && ($_->can('varname') ? ($_->varname // '') : '') eq '$self'
    } $g->nodes->@*;
    ok(defined $recv, 'the receiver is a $self PadAccess');
    is(($recv->stamp ? $recv->stamp->type : undef), 'Object',
        'the $self receiver is Object-stamped');
    ok(!defined $recv->inputs->[0], 'the $self receiver has no VarDecl input');
};

done_testing();
