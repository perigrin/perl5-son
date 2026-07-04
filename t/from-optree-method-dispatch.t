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
};

done_testing();
