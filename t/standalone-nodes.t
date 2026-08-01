# ABOUTME: Tests for 9 standalone node types (TernaryExpr, TryCatch, BacktickExpr,
# ABOUTME: StructRef, StructFieldAccess, AnonSub, RegexMatch, RegexSubst, VarDecl).

use v5.42.0;
use Test2::V0;

use SoN::IR::NodeFactory;
use SoN::IR::Stamp;

my $factory = SoN::IR::NodeFactory->new;
my $stamp = SoN::IR::Stamp->new(type => 'Str');

# Nodes are built through the factory, not by direct ->new: SoN::IR::Node
# requires an explicit content-hash id that only the factory assigns
# (SoN::IR::Node auto-generated one; SoN::IR::Node does not).
sub const ($val) {
    $factory->make('Constant', value => $val, stamp => $stamp)
}

# -----------------------------------------------------------------------
# Simple nodes — no extra fields, default content_hash from base class
# -----------------------------------------------------------------------

subtest 'TernaryExpr isa Node with correct operation' => sub {
    my $cond  = const(1);
    my $true  = const('yes');
    my $false = const('no');
    my $node  = $factory->make('TernaryExpr', inputs => [$cond, $true, $false]);

    isa_ok($node, ['SoN::IR::Node'], 'TernaryExpr isa Node');
    is($node->operation, 'TernaryExpr', 'operation is TernaryExpr');
    is(scalar $node->inputs->@*, 3, 'has 3 inputs');
};

subtest 'TernaryExpr content_hash uses base class format' => sub {
    my $cond = const(0);
    my $t    = const('a');
    my $f    = const('b');
    my $node = $factory->make('TernaryExpr', inputs => [$cond, $t, $f]);
    my $hash = $node->content_hash;

    like($hash, qr/TernaryExpr/, 'content_hash contains TernaryExpr');
    for my $inp ($cond, $t, $f) {
        like($hash, qr/\Q${\$inp->id}\E/, 'content_hash contains input id');
    }
};

subtest 'TryCatch isa Node with correct operation' => sub {
    my $body    = const('body');
    my $handler = const('handler');
    my $node    = $factory->make('TryCatch', inputs => [$body, $handler]);

    isa_ok($node, ['SoN::IR::Node'], 'TryCatch isa Node');
    is($node->operation, 'TryCatch', 'operation is TryCatch');
    is(scalar $node->inputs->@*, 2, 'has 2 inputs');
};

subtest 'TryCatch content_hash uses base class format' => sub {
    my $body    = const('try_body');
    my $handler = const('catch_handler');
    my $node    = $factory->make('TryCatch', inputs => [$body, $handler]);
    my $hash    = $node->content_hash;

    like($hash, qr/TryCatch/, 'content_hash contains TryCatch');
    for my $inp ($body, $handler) {
        like($hash, qr/\Q${\$inp->id}\E/, 'content_hash contains input id');
    }
};

subtest 'BacktickExpr isa Node with correct operation' => sub {
    my $cmd  = const('ls -la');
    my $node = $factory->make('BacktickExpr', inputs => [$cmd]);

    isa_ok($node, ['SoN::IR::Node'], 'BacktickExpr isa Node');
    is($node->operation, 'BacktickExpr', 'operation is BacktickExpr');
    is(scalar $node->inputs->@*, 1, 'has 1 input');
};

subtest 'BacktickExpr content_hash uses base class format' => sub {
    my $cmd  = const('echo hi');
    my $node = $factory->make('BacktickExpr', inputs => [$cmd]);
    my $hash = $node->content_hash;

    like($hash, qr/BacktickExpr/, 'content_hash contains BacktickExpr');
    like($hash, qr/\Q${\$cmd->id}\E/, 'content_hash contains input id');
};

subtest 'StructRef isa Node with correct operation' => sub {
    my $orig = const('some_hash');
    my $node = $factory->make('StructRef', inputs => [$orig]);

    isa_ok($node, ['SoN::IR::Node'], 'StructRef isa Node');
    is($node->operation, 'StructRef', 'operation is StructRef');
    is(scalar $node->inputs->@*, 1, 'has 1 input');
};

subtest 'StructRef content_hash uses base class format' => sub {
    my $orig = const('hash_val');
    my $node = $factory->make('StructRef', inputs => [$orig]);
    my $hash = $node->content_hash;

    like($hash, qr/StructRef/, 'content_hash contains StructRef');
    like($hash, qr/\Q${\$orig->id}\E/, 'content_hash contains input id');
};

subtest 'StructFieldAccess isa Node with correct operation' => sub {
    my $struct = const('struct_val');
    my $node   = $factory->make('StructFieldAccess', inputs => [$struct]);

    isa_ok($node, ['SoN::IR::Node'], 'StructFieldAccess isa Node');
    is($node->operation, 'StructFieldAccess', 'operation is StructFieldAccess');
    is(scalar $node->inputs->@*, 1, 'has 1 input');
};

subtest 'StructFieldAccess content_hash uses base class format' => sub {
    my $struct = const('struct_base');
    my $node   = $factory->make('StructFieldAccess', inputs => [$struct]);
    my $hash   = $node->content_hash;

    like($hash, qr/StructFieldAccess/, 'content_hash contains StructFieldAccess');
    like($hash, qr/\Q${\$struct->id}\E/, 'content_hash contains input id');
};

subtest 'AnonSub isa Node with correct operation' => sub {
    my $body = const('sub_body');
    my $node = $factory->make('AnonSub', inputs => [$body]);

    isa_ok($node, ['SoN::IR::Node'], 'AnonSub isa Node');
    is($node->operation, 'AnonSub', 'operation is AnonSub');
    is(scalar $node->inputs->@*, 1, 'has 1 input');
};

subtest 'AnonSub content_hash uses base class format' => sub {
    my $body = const('closure_body');
    my $node = $factory->make('AnonSub', inputs => [$body]);
    my $hash = $node->content_hash;

    like($hash, qr/AnonSub/, 'content_hash contains AnonSub');
    like($hash, qr/\Q${\$body->id}\E/, 'content_hash contains input id');
};

# -----------------------------------------------------------------------
# Nodes with custom fields and content_hash
# -----------------------------------------------------------------------

subtest 'RegexMatch isa Node with pattern and flags fields' => sub {
    my $input = const('some_string');
    my $node  = $factory->make('RegexMatch',
        pattern => 'foo\d+',
        inputs  => [$input],
    );

    isa_ok($node, ['SoN::IR::Node'], 'RegexMatch isa Node');
    is($node->operation, 'RegexMatch',  'operation is RegexMatch');
    is($node->pattern,   'foo\d+',      'pattern accessor returns correct value');
    is($node->flags,     '',            'flags defaults to empty string');
};

subtest 'RegexMatch accepts non-empty flags' => sub {
    my $input = const('text');
    my $node  = $factory->make('RegexMatch',
        pattern => '\w+',
        flags   => 'gi',
        inputs  => [$input],
    );

    is($node->flags, 'gi', 'flags accessor returns provided value');
};

subtest 'RegexMatch content_hash includes pattern, flags, and input ids' => sub {
    my $input = const('haystack');
    my $node  = $factory->make('RegexMatch',
        pattern => 'needle',
        flags   => 'i',
        inputs  => [$input],
    );
    my $hash = $node->content_hash;

    like($hash, qr/RegexMatch/,           'content_hash contains RegexMatch');
    like($hash, qr/pattern=needle/,       'content_hash contains pattern');
    like($hash, qr/flags=i/,              'content_hash contains flags');
    like($hash, qr/\Q${\$input->id}\E/,   'content_hash contains input id');
};

# RegexMatch is a %STATEMENT_EFFECT_OPS entry in SoN::IR::NodeFactory:
# a match executes against its subject and writes capture state, so two
# textually-identical matches at different program points are distinct
# effects (never hash-consed by content), unlike SoN::IR::NodeFactory.
subtest 'RegexMatch is never hash-consed: every make() call is a distinct match' => sub {
    my $input   = const('text');

    my $n1 = $factory->make('RegexMatch', pattern => 'abc', flags => '', inputs => [$input]);
    my $n2 = $factory->make('RegexMatch', pattern => 'abc', flags => '', inputs => [$input]);
    my $n3 = $factory->make('RegexMatch', pattern => 'xyz', flags => '', inputs => [$input]);

    isnt($n1->id, $n2->id, 'two matches with identical pattern+flags+inputs still get distinct ids');
    isnt($n1->id, $n3->id, 'different pattern also gives a distinct id');
};

subtest 'RegexSubst isa Node with pattern, replacement, and flags fields' => sub {
    my $input = const('input_string');
    my $node  = $factory->make('RegexSubst',
        pattern     => 'foo',
        replacement => 'bar',
        inputs      => [$input],
    );

    isa_ok($node, ['SoN::IR::Node'], 'RegexSubst isa Node');
    is($node->operation,   'RegexSubst', 'operation is RegexSubst');
    is($node->pattern,     'foo',        'pattern accessor returns correct value');
    is($node->replacement, 'bar',        'replacement accessor returns correct value');
    is($node->flags,       '',           'flags defaults to empty string');
};

subtest 'RegexSubst accepts non-empty flags' => sub {
    my $input = const('text');
    my $node  = $factory->make('RegexSubst',
        pattern     => '\s+',
        replacement => ' ',
        flags       => 'g',
        inputs      => [$input],
    );

    is($node->flags, 'g', 'flags accessor returns provided value');
};

subtest 'RegexSubst content_hash includes pattern, replacement, flags, and input ids' => sub {
    my $input = const('subject');
    my $node  = $factory->make('RegexSubst',
        pattern     => 'old',
        replacement => 'new',
        flags       => 'g',
        inputs      => [$input],
    );
    my $hash = $node->content_hash;

    like($hash, qr/RegexSubst/,         'content_hash contains RegexSubst');
    like($hash, qr/pattern=old/,        'content_hash contains pattern');
    like($hash, qr/replacement=new/,    'content_hash contains replacement');
    like($hash, qr/flags=g/,            'content_hash contains flags');
    like($hash, qr/\Q${\$input->id}\E/, 'content_hash contains input id');
};

# RegexSubst is a %STATEMENT_EFFECT_OPS entry in SoN::IR::NodeFactory:
# a substitution mutates its subject, so two textually-identical
# substitutions at different program points are distinct effects (never
# hash-consed by content), unlike SoN::IR::NodeFactory.
subtest 'RegexSubst is never hash-consed: every make() call is a distinct substitution' => sub {
    my $input   = const('text');

    my $n1 = $factory->make('RegexSubst',
        pattern => 'a', replacement => 'b', flags => '', inputs => [$input]);
    my $n2 = $factory->make('RegexSubst',
        pattern => 'a', replacement => 'b', flags => '', inputs => [$input]);
    my $n3 = $factory->make('RegexSubst',
        pattern => 'a', replacement => 'c', flags => '', inputs => [$input]);

    isnt($n1->id, $n2->id, 'two substitutions with identical pattern+replacement+flags+inputs still get distinct ids');
    isnt($n1->id, $n3->id, 'different replacement also gives a distinct id');
};

subtest 'VarDecl isa Node with scope field' => sub {
    my $var  = const('$x');
    my $node = $factory->make('VarDecl', scope => 'my', inputs => [$var]);

    isa_ok($node, ['SoN::IR::Node'], 'VarDecl isa Node');
    is($node->operation, 'VarDecl', 'operation is VarDecl');
    is($node->scope,     'my',      'scope accessor returns correct value');
};

# SoN::IR::Node::VarDecl::content_hash() returns $self->id() rather than a
# descriptive "VarDecl|scope=...|input_id" string (unlike
# SoN::IR::Node::VarDecl). This is deliberate: VarDecl is a
# %STATEMENT_EFFECT_OPS-style per-position node in Chalk (two textually
# identical declarations at different control positions are distinct
# nodes), so its content_hash IS its unique id, not a structural digest.
subtest 'VarDecl content_hash is the node id (per-position identity)' => sub {
    my $var  = const('$count');
    my $node = $factory->make('VarDecl', scope => 'local', inputs => [$var]);

    is($node->content_hash, $node->id, 'content_hash equals id for VarDecl');
    like($node->id, qr/^VarDecl#/, 'id carries the VarDecl per-position counter');
};

# VarDecl is allocated fresh on every make() call in SoN::IR::NodeFactory
# (see %STATEMENT_EFFECT_OPS handling) -- never hash-consed by scope+inputs,
# unlike SoN::IR::NodeFactory::make. Two calls with identical scope and
# inputs are still distinct declarations at distinct control positions.
subtest 'VarDecl is never hash-consed: every make() call is a distinct declaration' => sub {
    my $var     = const('$y');

    my $n1 = $factory->make('VarDecl', scope => 'my',    inputs => [$var]);
    my $n2 = $factory->make('VarDecl', scope => 'my',    inputs => [$var]);
    my $n3 = $factory->make('VarDecl', scope => 'local', inputs => [$var]);

    isnt($n1->id, $n2->id, 'two declarations with identical scope+inputs still get distinct ids');
    isnt($n1->id, $n3->id, 'different scope also gives a distinct id');
};

# -----------------------------------------------------------------------
# NodeFactory registration for all 9 nodes
# -----------------------------------------------------------------------

subtest 'NodeFactory can create all 9 standalone nodes' => sub {
    my $c = const('dummy');

    my $ternary = $factory->make('TernaryExpr', inputs => [$c, $c, $c]);
    isa_ok($ternary, ['SoN::IR::Node'], 'factory TernaryExpr isa Node');
    is($ternary->operation, 'TernaryExpr', 'factory TernaryExpr operation');

    my $tc = $factory->make('TryCatch', inputs => [$c, $c]);
    isa_ok($tc, ['SoN::IR::Node'], 'factory TryCatch isa Node');
    is($tc->operation, 'TryCatch', 'factory TryCatch operation');

    my $bt = $factory->make('BacktickExpr', inputs => [$c]);
    isa_ok($bt, ['SoN::IR::Node'], 'factory BacktickExpr isa Node');
    is($bt->operation, 'BacktickExpr', 'factory BacktickExpr operation');

    my $sr = $factory->make('StructRef', inputs => [$c]);
    isa_ok($sr, ['SoN::IR::Node'], 'factory StructRef isa Node');
    is($sr->operation, 'StructRef', 'factory StructRef operation');

    my $sfa = $factory->make('StructFieldAccess', inputs => [$c]);
    isa_ok($sfa, ['SoN::IR::Node'], 'factory StructFieldAccess isa Node');
    is($sfa->operation, 'StructFieldAccess', 'factory StructFieldAccess operation');

    my $as = $factory->make('AnonSub', inputs => [$c]);
    isa_ok($as, ['SoN::IR::Node'], 'factory AnonSub isa Node');
    is($as->operation, 'AnonSub', 'factory AnonSub operation');

    my $rm = $factory->make('RegexMatch', pattern => 'x', inputs => [$c]);
    isa_ok($rm, ['SoN::IR::Node'], 'factory RegexMatch isa Node');
    is($rm->operation, 'RegexMatch', 'factory RegexMatch operation');

    my $rs = $factory->make('RegexSubst', pattern => 'x', replacement => 'y', inputs => [$c]);
    isa_ok($rs, ['SoN::IR::Node'], 'factory RegexSubst isa Node');
    is($rs->operation, 'RegexSubst', 'factory RegexSubst operation');

    my $vd = $factory->make('VarDecl', scope => 'my', inputs => [$c]);
    isa_ok($vd, ['SoN::IR::Node'], 'factory VarDecl isa Node');
    is($vd->operation, 'VarDecl', 'factory VarDecl operation');
};

done_testing;
