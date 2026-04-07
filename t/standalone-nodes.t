# ABOUTME: Tests for 9 standalone node types (TernaryExpr, TryCatch, BacktickExpr,
# ABOUTME: StructRef, StructFieldAccess, AnonSub, RegexMatch, RegexSubst, VarDecl).

use v5.42.0;
use Test2::V0;

use SoN::IR::Node;
use SoN::IR::Node::Constant;
use SoN::IR::Stamp;

my $stamp = SoN::IR::Stamp->new(type => 'Str');

sub const ($val) {
    SoN::IR::Node::Constant->new(value => $val, stamp => $stamp)
}

# -----------------------------------------------------------------------
# Simple nodes — no extra fields, default content_hash from base class
# -----------------------------------------------------------------------

subtest 'TernaryExpr isa Node with correct operation' => sub {
    use SoN::IR::Node::TernaryExpr;
    my $cond  = const(1);
    my $true  = const('yes');
    my $false = const('no');
    my $node  = SoN::IR::Node::TernaryExpr->new(inputs => [$cond, $true, $false]);

    isa_ok($node, ['SoN::IR::Node'], 'TernaryExpr isa Node');
    is($node->operation, 'TernaryExpr', 'operation is TernaryExpr');
    is(scalar $node->inputs->@*, 3, 'has 3 inputs');
};

subtest 'TernaryExpr content_hash uses base class format' => sub {
    use SoN::IR::Node::TernaryExpr;
    my $cond = const(0);
    my $t    = const('a');
    my $f    = const('b');
    my $node = SoN::IR::Node::TernaryExpr->new(inputs => [$cond, $t, $f]);
    my $hash = $node->content_hash;

    like($hash, qr/TernaryExpr/, 'content_hash contains TernaryExpr');
    for my $inp ($cond, $t, $f) {
        like($hash, qr/\Q${\$inp->id}\E/, 'content_hash contains input id');
    }
};

subtest 'TryCatch isa Node with correct operation' => sub {
    use SoN::IR::Node::TryCatch;
    my $body    = const('body');
    my $handler = const('handler');
    my $node    = SoN::IR::Node::TryCatch->new(inputs => [$body, $handler]);

    isa_ok($node, ['SoN::IR::Node'], 'TryCatch isa Node');
    is($node->operation, 'TryCatch', 'operation is TryCatch');
    is(scalar $node->inputs->@*, 2, 'has 2 inputs');
};

subtest 'TryCatch content_hash uses base class format' => sub {
    use SoN::IR::Node::TryCatch;
    my $body    = const('try_body');
    my $handler = const('catch_handler');
    my $node    = SoN::IR::Node::TryCatch->new(inputs => [$body, $handler]);
    my $hash    = $node->content_hash;

    like($hash, qr/TryCatch/, 'content_hash contains TryCatch');
    for my $inp ($body, $handler) {
        like($hash, qr/\Q${\$inp->id}\E/, 'content_hash contains input id');
    }
};

subtest 'BacktickExpr isa Node with correct operation' => sub {
    use SoN::IR::Node::BacktickExpr;
    my $cmd  = const('ls -la');
    my $node = SoN::IR::Node::BacktickExpr->new(inputs => [$cmd]);

    isa_ok($node, ['SoN::IR::Node'], 'BacktickExpr isa Node');
    is($node->operation, 'BacktickExpr', 'operation is BacktickExpr');
    is(scalar $node->inputs->@*, 1, 'has 1 input');
};

subtest 'BacktickExpr content_hash uses base class format' => sub {
    use SoN::IR::Node::BacktickExpr;
    my $cmd  = const('echo hi');
    my $node = SoN::IR::Node::BacktickExpr->new(inputs => [$cmd]);
    my $hash = $node->content_hash;

    like($hash, qr/BacktickExpr/, 'content_hash contains BacktickExpr');
    like($hash, qr/\Q${\$cmd->id}\E/, 'content_hash contains input id');
};

subtest 'StructRef isa Node with correct operation' => sub {
    use SoN::IR::Node::StructRef;
    my $orig = const('some_hash');
    my $node = SoN::IR::Node::StructRef->new(inputs => [$orig]);

    isa_ok($node, ['SoN::IR::Node'], 'StructRef isa Node');
    is($node->operation, 'StructRef', 'operation is StructRef');
    is(scalar $node->inputs->@*, 1, 'has 1 input');
};

subtest 'StructRef content_hash uses base class format' => sub {
    use SoN::IR::Node::StructRef;
    my $orig = const('hash_val');
    my $node = SoN::IR::Node::StructRef->new(inputs => [$orig]);
    my $hash = $node->content_hash;

    like($hash, qr/StructRef/, 'content_hash contains StructRef');
    like($hash, qr/\Q${\$orig->id}\E/, 'content_hash contains input id');
};

subtest 'StructFieldAccess isa Node with correct operation' => sub {
    use SoN::IR::Node::StructFieldAccess;
    my $struct = const('struct_val');
    my $node   = SoN::IR::Node::StructFieldAccess->new(inputs => [$struct]);

    isa_ok($node, ['SoN::IR::Node'], 'StructFieldAccess isa Node');
    is($node->operation, 'StructFieldAccess', 'operation is StructFieldAccess');
    is(scalar $node->inputs->@*, 1, 'has 1 input');
};

subtest 'StructFieldAccess content_hash uses base class format' => sub {
    use SoN::IR::Node::StructFieldAccess;
    my $struct = const('struct_base');
    my $node   = SoN::IR::Node::StructFieldAccess->new(inputs => [$struct]);
    my $hash   = $node->content_hash;

    like($hash, qr/StructFieldAccess/, 'content_hash contains StructFieldAccess');
    like($hash, qr/\Q${\$struct->id}\E/, 'content_hash contains input id');
};

subtest 'AnonSub isa Node with correct operation' => sub {
    use SoN::IR::Node::AnonSub;
    my $body = const('sub_body');
    my $node = SoN::IR::Node::AnonSub->new(inputs => [$body]);

    isa_ok($node, ['SoN::IR::Node'], 'AnonSub isa Node');
    is($node->operation, 'AnonSub', 'operation is AnonSub');
    is(scalar $node->inputs->@*, 1, 'has 1 input');
};

subtest 'AnonSub content_hash uses base class format' => sub {
    use SoN::IR::Node::AnonSub;
    my $body = const('closure_body');
    my $node = SoN::IR::Node::AnonSub->new(inputs => [$body]);
    my $hash = $node->content_hash;

    like($hash, qr/AnonSub/, 'content_hash contains AnonSub');
    like($hash, qr/\Q${\$body->id}\E/, 'content_hash contains input id');
};

# -----------------------------------------------------------------------
# Nodes with custom fields and content_hash
# -----------------------------------------------------------------------

subtest 'RegexMatch isa Node with pattern and flags fields' => sub {
    use SoN::IR::Node::RegexMatch;
    my $input = const('some_string');
    my $node  = SoN::IR::Node::RegexMatch->new(
        pattern => 'foo\d+',
        inputs  => [$input],
    );

    isa_ok($node, ['SoN::IR::Node'], 'RegexMatch isa Node');
    is($node->operation, 'RegexMatch',  'operation is RegexMatch');
    is($node->pattern,   'foo\d+',      'pattern accessor returns correct value');
    is($node->flags,     '',            'flags defaults to empty string');
};

subtest 'RegexMatch accepts non-empty flags' => sub {
    use SoN::IR::Node::RegexMatch;
    my $input = const('text');
    my $node  = SoN::IR::Node::RegexMatch->new(
        pattern => '\w+',
        flags   => 'gi',
        inputs  => [$input],
    );

    is($node->flags, 'gi', 'flags accessor returns provided value');
};

subtest 'RegexMatch content_hash includes pattern, flags, and input ids' => sub {
    use SoN::IR::Node::RegexMatch;
    my $input = const('haystack');
    my $node  = SoN::IR::Node::RegexMatch->new(
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

subtest 'RegexMatch is hash-consed by pattern, flags, and inputs' => sub {
    use SoN::IR::Node::RegexMatch;
    use SoN::IR::NodeFactory;
    my $factory = SoN::IR::NodeFactory->new;
    my $input   = const('text');

    my $n1 = $factory->make('RegexMatch', pattern => 'abc', flags => '', inputs => [$input]);
    my $n2 = $factory->make('RegexMatch', pattern => 'abc', flags => '', inputs => [$input]);
    my $n3 = $factory->make('RegexMatch', pattern => 'xyz', flags => '', inputs => [$input]);

    is($n1->id, $n2->id, 'same pattern+flags+inputs returns same node');
    isnt($n1->id, $n3->id, 'different pattern returns different node');
};

subtest 'RegexSubst isa Node with pattern, replacement, and flags fields' => sub {
    use SoN::IR::Node::RegexSubst;
    my $input = const('input_string');
    my $node  = SoN::IR::Node::RegexSubst->new(
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
    use SoN::IR::Node::RegexSubst;
    my $input = const('text');
    my $node  = SoN::IR::Node::RegexSubst->new(
        pattern     => '\s+',
        replacement => ' ',
        flags       => 'g',
        inputs      => [$input],
    );

    is($node->flags, 'g', 'flags accessor returns provided value');
};

subtest 'RegexSubst content_hash includes pattern, replacement, flags, and input ids' => sub {
    use SoN::IR::Node::RegexSubst;
    my $input = const('subject');
    my $node  = SoN::IR::Node::RegexSubst->new(
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

subtest 'RegexSubst is hash-consed by pattern, replacement, flags, and inputs' => sub {
    use SoN::IR::Node::RegexSubst;
    use SoN::IR::NodeFactory;
    my $factory = SoN::IR::NodeFactory->new;
    my $input   = const('text');

    my $n1 = $factory->make('RegexSubst',
        pattern => 'a', replacement => 'b', flags => '', inputs => [$input]);
    my $n2 = $factory->make('RegexSubst',
        pattern => 'a', replacement => 'b', flags => '', inputs => [$input]);
    my $n3 = $factory->make('RegexSubst',
        pattern => 'a', replacement => 'c', flags => '', inputs => [$input]);

    is($n1->id, $n2->id, 'same pattern+replacement+flags+inputs returns same node');
    isnt($n1->id, $n3->id, 'different replacement returns different node');
};

subtest 'VarDecl isa Node with scope field' => sub {
    use SoN::IR::Node::VarDecl;
    my $var  = const('$x');
    my $node = SoN::IR::Node::VarDecl->new(scope => 'my', inputs => [$var]);

    isa_ok($node, ['SoN::IR::Node'], 'VarDecl isa Node');
    is($node->operation, 'VarDecl', 'operation is VarDecl');
    is($node->scope,     'my',      'scope accessor returns correct value');
};

subtest 'VarDecl content_hash includes scope and input ids' => sub {
    use SoN::IR::Node::VarDecl;
    my $var  = const('$count');
    my $node = SoN::IR::Node::VarDecl->new(scope => 'local', inputs => [$var]);
    my $hash = $node->content_hash;

    like($hash, qr/VarDecl/,            'content_hash contains VarDecl');
    like($hash, qr/scope=local/,        'content_hash contains scope');
    like($hash, qr/\Q${\$var->id}\E/,   'content_hash contains input id');
};

subtest 'VarDecl is hash-consed by scope and inputs' => sub {
    use SoN::IR::Node::VarDecl;
    use SoN::IR::NodeFactory;
    my $factory = SoN::IR::NodeFactory->new;
    my $var     = const('$y');

    my $n1 = $factory->make('VarDecl', scope => 'my',    inputs => [$var]);
    my $n2 = $factory->make('VarDecl', scope => 'my',    inputs => [$var]);
    my $n3 = $factory->make('VarDecl', scope => 'local', inputs => [$var]);

    is($n1->id, $n2->id, 'same scope+inputs returns same node');
    isnt($n1->id, $n3->id, 'different scope returns different node');
};

# -----------------------------------------------------------------------
# NodeFactory registration for all 9 nodes
# -----------------------------------------------------------------------

subtest 'NodeFactory can create all 9 standalone nodes' => sub {
    use SoN::IR::NodeFactory;
    my $factory = SoN::IR::NodeFactory->new;

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
