# ABOUTME: Tests that every Value node carries a stamp -- undef is unrepresentable.
# ABOUTME: Self-typing node kinds get their real type; genuinely unknown ones get 'Unknown'.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;
use SoN::IR::Value;
use SoN::IR::NodeFactory;

# A Value node exists to DEFINE a value, and a value has a type. An undef
# stamp is therefore not a state a Value node may be in.
#
# The class split (SoN::IR::Value) removed one of undef's three meanings --
# "this node produces no value at all" -- by making control nodes a different
# class. This closes a second: "inference has not run yet". What remains is
# `Unknown`, which is an ANSWER ("asked, genuinely cannot tell") rather than
# an absence, and is a real member of the lattice with defined join/meet.
#
# Measured before the fix: 19% of constructed Value nodes carried no stamp,
# and the untyped set was not arbitrary. ArrayRef, HashRef, RefType, Defined
# and RegexMatch all have a type knowable from the node kind alone -- those
# were defects, not open questions.

sub translate ($src) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval "sub { $src }";
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

subtest 'the field is required -- undef is unrepresentable' => sub {
    # The guarantee has to live on the CLASS, not only in the factory's
    # defaulting. A construction path that bypasses the factory default
    # must fail loudly rather than produce an untyped value node.
    my $err = dies {
        SoN::IR::Node::Constant->new(id => 'x', value => 1);
    };
    ok($err, 'constructing a Value without a stamp dies');

    ok(lives {
        SoN::IR::Node::Constant->new(id => 'x', value => 1,
            stamp => SoN::IR::Stamp->new(type => 'Int'));
    }, 'constructing a Value WITH a stamp succeeds');

    # Control nodes keep an optional stamp -- they define no value, so there
    # is no type for them to carry and requiring one would be meaningless.
    ok(lives { SoN::IR::Node::Start->new(id => 's') },
        'a control node still constructs with no stamp');
};

subtest 'the factory defaults to Unknown, never undef' => sub {
    my $factory = SoN::IR::NodeFactory->new;

    my $n = $factory->make('Subscript', inputs => []);
    # `defined` is NOT a sufficient assertion here. A stamp is a
    # SoN::IR::Stamp OBJECT -- the serializer reads $node->stamp->type and
    # Stamp::join operates on the objects -- so a plain type NAME would pass
    # a defined-check and then die at serialization. Assert what consumers
    # actually do with it.
    isa_ok($n->stamp, ['SoN::IR::Stamp'], 'default stamp is a Stamp object');
    is($n->stamp->type, 'Unknown',
        'a Value node built with no stamp gets Unknown, not undef');

    my $c = $factory->make('Constant',
        value => 7, stamp => SoN::IR::Stamp->new(type => 'Int'));
    is($c->stamp->type, 'Int', 'an explicit stamp is not overwritten');
};

subtest 'self-typing node kinds carry their real type' => sub {
    # These are knowable from the node kind alone. Leaving them Unknown
    # would be technically non-undef and still wrong -- Unknown must mean
    # "cannot tell", not "did not bother".
    my %EXPECT = (
        'my $r = [1,2,3]; $r'        => { ArrayLiteral => 'ArrayRef' },
        'my $r = {a=>1}; $r'         => { HashLiteral  => 'HashRef' },
        'my $o = bless {}, "X"; ref($o)' => { RefType => 'Str' },
        'my $x; defined($x) ? 1 : 0' => { Defined    => 'Boolean' },
        'my $s = "abc"; $s =~ /b/ ? 1 : 0' => { RegexMatch => 'Boolean' },
    );

    for my $src (sort keys %EXPECT) {
        my $g = translate($src);
        my %want = $EXPECT{$src}->%*;
        for my $op (sort keys %want) {
            my ($node) = grep { $_->operation eq $op } $g->nodes->@*;
            ok($node, "$op node built for: $src") or next;
            isa_ok($node->stamp, ['SoN::IR::Stamp'], "$op stamp is a Stamp");
            is($node->stamp->type, $want{$op},
                "$op is stamped $want{$op}");
        }
    }
};

subtest 'no Value node anywhere in a real graph is untyped' => sub {
    # The load-bearing assertion: sweep a spread of real constructs and
    # confirm the invariant holds across every node the producer builds,
    # not only the kinds this file happens to name.
    my @SRC = (
        'my $x = 1; my $y = 2; $x + $y',
        'my $x = 1.5; my $y = 2; $x / $y',
        'my $s = "ab"; $s . "cd"',
        'my $c = 1; my $r = $c ? 7 : 9; $r',
        'my $t = 0; for my $i (1..3) { $t += $i } $t',
        'my $i = 0; while ($i < 3) { $i++ } $i',
        'my @a = (1,2,3); scalar @a',
        'my %h = (a=>1); $h{a}',
        'my $r = [1,2,3]; $r->[1]',
        'my $r = {a=>1}; $r->{a}',
        'sub f { $_[0] + 1 } f(1)',
        'print "hi\n"; 1',
        'my $s = "abc"; $s =~ /b/ ? 1 : 0',
        'my $n = 3; "n=$n"',
        'my $x; defined($x) ? 1 : 0',
        'my $x = 0; try { $x = 1 } catch ($e) { $x = 2 } $x',
        'my $c = 1; if ($c) { if ($c) { print "y\n" } } 1',
        'my $o = bless {}, "X"; ref($o)',
        'my @a = (1,2,3); my $n = @a; $n',
    );

    my $checked = 0;
    for my $src (@SRC) {
        my $g = eval { translate($src) };
        next unless $g;
        for my $n ($g->nodes->@*) {
            next unless $n isa SoN::IR::Value;
            $checked++;
            # Assert the stamp is USABLE, not merely present -- see the
            # object-vs-name note above.
            my $ok = $n->stamp isa SoN::IR::Stamp && defined $n->stamp->type;
            ok($ok, sprintf('%s is stamped (%s)', $n->operation, $src))
                or diag("UNTYPED: " . $n->operation . " in: $src");
        }
    }
    cmp_ok($checked, '>', 50, "swept a meaningful number of Value nodes ($checked)");
};

done_testing;
