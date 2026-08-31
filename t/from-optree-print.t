# ABOUTME: print LISTOP builds a Print node (op 'Print') over its whole arg
# ABOUTME: list, control-pinned; explicit-filehandle and coerce-needing forms GAP.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# Translate a code string under rpeep suppression (the production -MO=SoN path)
# and return the graph, or die on GAP/compile error.
sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $cerr = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $cerr" if $cerr;
    return SoN::FromOptree->translate($cv);
}

sub prints ($g) {
    return grep { $_->operation eq 'Print' } $g->nodes->@*;
}

sub is_effect ($n) {
    return defined $n->control_in;
}

# --- 1. a bare literal-list print builds ONE Print node over ALL its args ---
subtest 'print of a literal list -> Print node with every element' => sub {
    my $g = translate('sub { print "ok ", 1, "\n"; 1 }');
    my @p = prints($g);
    is(scalar @p, 1, 'exactly one Print node') or diag(
        'ops = [' . join(' ', map { $_->operation } $g->nodes->@*) . ']');
    my $p = $p[0];

    # control is carried on control_in (produce-time control), not in inputs;
    # inputs are the three list elements ("ok ", 1, "\n").
    ok(is_effect($p), 'Print is a statement effect (control-pinned)');
    my @in = $p->inputs->@*;
    is(scalar @in, 3, 'all three list elements are inputs to Print')
        or diag('inputs = [' . join(' ', map { $_->operation } @in) . ']');

    # Print's signature is Print(Str...), so a non-Str element arrives through
    # an explicit Stringify coercion rather than Print knowing how to render an
    # Int itself. The Str literals pass straight through.
    is($in[0]->operation, 'Constant',  'the leading Str literal is direct');
    is($in[1]->operation, 'Coerce', 'the Int element is coerced to Str');
    is($in[1]->to_repr, 'Str',       '... by a Coerce(X -> Str)');
    is($in[1]->inputs->[0]->value, 1,  '... wrapping the original value');
    is($in[2]->operation, 'Constant',  'the trailing Str literal is direct');
};

# --- 2. single-arg print ---
subtest 'print of a single string -> Print node' => sub {
    my $g = translate('sub { print "hi\n"; 1 }');
    my @p = prints($g);
    is(scalar @p, 1, 'one Print node');
    ok(is_effect($p[0]), 'control-pinned');
};

# --- 3. two prints stay two distinct, ordered effects ---
subtest 'two prints -> two Print effects on the control chain' => sub {
    my $g = translate('sub { print "a\n"; print "b\n"; 1 }');
    my @p = prints($g);
    is(scalar @p, 2, 'two Print nodes, neither dropped')
        or diag('ops = [' . join(' ', map { $_->operation } $g->nodes->@*) . ']');
};

# --- 4. print to an explicit filehandle (OPf_STACKED) NAMES the handle ---
#
# These two used to assert a GAP, on the grounds that the runtime-free backend
# writes only to stdout so honoring a handle would misroute. That is a T2
# judgement -- can this TARGET represent a filehandle -- made inside T1, whose
# job is to state what the program does. The producer names the operation and
# the consumer decides whether it can lower it.
#
# The concern the old title named -- "never a silent fd-1 misroute" -- is
# unchanged and is what these now pin: the handle is IN the graph as operand 0
# with has_filehandle set, so nothing can quietly route to fd 1. A consumer
# that cannot honor a handle refuses on a Print that says it has one.
subtest 'print STDOUT ... names the handle, never a silent fd-1 misroute' => sub {
    my $g = translate('sub { print STDOUT "x\n"; 1 }');
    my @p = prints($g);
    is(scalar @p, 1, 'a Print node is built rather than refused') or return;
    ok($p[0]->has_filehandle, 'and it says it targets an explicit handle');
    is($p[0]->inputs->[0]->value, 'STDOUT', 'the handle is operand 0');
};

subtest 'print $fh ... names the lexical handle' => sub {
    my $g = translate('sub { my $fh; print $fh "x\n"; 1 }');
    my @p = prints($g);
    is(scalar @p, 1, 'a Print node is built') or return;
    ok($p[0]->has_filehandle, 'it says it targets an explicit handle');
    is(scalar($p[0]->inputs->@*), 2, 'handle plus argument');
};

# --- 5. interpolated print: the multiconcat arg decodes to a runtime-free
# Concat, so print emits it as a Print over that one value (NOT dropped). ---
subtest 'interpolated print -> Print over the concatenated value' => sub {
    my $g = translate('sub { my $n = 1; print "ok $n\n"; 1 }');
    my @p = prints($g);
    is(scalar @p, 1, 'one Print node, arg not dropped')
        or diag('ops = [' . join(' ', map { $_->operation } $g->nodes->@*) . ']');
    ok(is_effect($p[0]), 'control-pinned');
};

done_testing;
