# ABOUTME: Tests SoN::FromOptree refuses string eval by name, not via a constructor error.
# ABOUTME: entereval's body has never been compiled when B::SoN walks the optree.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;

# String eval is ONE op -- `entereval[t256] sK/1`, a unary op consuming the
# source string. Measured with B::Concise; block eval is the opposite shape
# (`entertry(other->N) ... leavetry`, a real region whose body IS in the
# optree).
#
# It cannot be compiled FROM HERE, and that is structural rather than unbuilt.
# B::SoN runs at CHECK time on an already-compiled optree: the entereval op is
# present but the eval'd code is not, because perl compiles that string only
# when the op EXECUTES. This holds for a CONSTANT operand too -- `eval q{1+2}`
# looks compilable because the string is known, but building it would mean
# invoking the perl compiler on that string mid-walk and splicing the result,
# which is a different tool, not a missing feature.
#
# Before this, translation died with "Required parameter 'value' is missing for
# SoN::IR::Node::Constant" -- loud, so nothing miscompiled, but naming Chalk's
# node class for what is really "string eval is not compiled". The cause was
# the walk descending into `hintseval`, entereval's SECOND child, which carries
# the lexical hints the eval'd code inherits and is compiler metadata rather
# than a value operand.
#
# NOTE ON eval BELOW: every eval() here is INERT. The coderefs are handed to
# translate(), which walks their optrees; nothing invokes them.

subtest 'string eval with a constant operand is refused by name' => sub {
    my $err = dies { SoN::FromOptree->translate(sub { my $r = eval q{1+2}; $r }) };

    ok($err, 'translation refuses rather than returning a graph');
    like($err, qr/GAP/, 'refusal is a GAP');
    like($err, qr/eval/, 'names the construct the user wrote');
    unlike($err, qr/Required parameter/,
        'does NOT leak a constructor error');
    unlike($err, qr/SoN::IR::Node/,
        'does NOT name an internal node class');
};

subtest 'string eval with a variable operand is refused too' => sub {
    # The form that is impossible under ANY architecture, not just this one:
    # the code does not exist until runtime.
    my $err = dies {
        SoN::FromOptree->translate(sub { my $c = q{1+2}; my $r = eval $c; $r })
    };
    ok($err, 'the variable-operand form refuses');
    like($err, qr/GAP/, 'refusal is a GAP');
};

subtest 'void-context string eval is refused' => sub {
    # A void eval discards its value but still must not vanish -- the same
    # silent-drop class as `write` and `goto`.
    my $err = dies { SoN::FromOptree->translate(sub { eval q{1}; 7 }) };
    ok($err, 'a void string eval refuses rather than being dropped');
    like($err, qr/GAP/, 'refusal is a GAP');
};

subtest 'ordinary code is untouched' => sub {
    # The refusal is keyed by op NAME. Nothing about adding it may disturb
    # constructs that already translate.
    ok(lives { SoN::FromOptree->translate(sub { my $x = 1; $x + 1 }) },
        'plain arithmetic still translates');
    ok(lives { SoN::FromOptree->translate(sub { my $t = 0; for my $i (1..3) { $t += $i } $t }) },
        'loops still translate');
};

# WHY IT IS REFUSED, pinned because the reason is easy to get wrong -- and was
# got wrong twice while writing this.
#
# `eval STRING` IS a Str -> Code coercion, and Code is a first-class value:
# `eval "sub { ... }"` returns a CODE ref you can store in a list, pass, and
# call. So it is an ordinary value conversion, not a special form.
#
# It is NOT refused for being a conversion between unrelated types.
# `meet(Str, Code)` is None -- but so is `meet(ArrayRef, Str)`, and the producer
# EMITS that coercion and perl lowers it to "ARRAY(0x...)". A None meet says the
# types share no common subtype; it says nothing about whether a conversion
# exists. Asserted here so nobody adds a `meet == None -> refuse` rule: it would
# break the working stringification path.
#
# It is refused because the conversion function IS the perl compiler, and
# B::SoN runs at CHECK time, before that function can be invoked.
subtest 'the refusal is about WHEN the compiler runs, not about types' => sub {
    my $err = dies { SoN::FromOptree->translate(sub { my $x = eval "1+1"; $x }) };
    like($err, qr/CHECK time|before it runs/,
        'the message names the timing, which is the actual reason');
};

# THE COUNTEREXAMPLE THAT DISPROVES THE TYPE-BASED RULE: a meet==None coercion
# the producer emits happily. If this ever GAPs, someone has added the
# `meet == None -> refuse` rule the comment above warns against.
subtest 'a meet==None coercion is still emitted where it is lowerable' => sub {
    my $g = SoN::FromOptree->translate(sub { my $r = [1,2]; print "x" . $r });
    ok($g, 'ArrayRef -> Str translates, though meet(ArrayRef,Str) is None')
        or return;
    my ($c) = grep { $_->operation eq 'Coerce' } $g->nodes->@*;
    ok($c, 'and it really is a Coerce node');
};

done_testing;