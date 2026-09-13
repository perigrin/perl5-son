# ABOUTME: A node naming a variable must carry its sigil -- $_ and @_ are different variables.
# ABOUTME: An absent sigil hash-conses them into one node, which is a silent merge.

use v5.42.0;
use Test2::V0;

use SoN::IR::NodeFactory;

my $f = SoN::IR::NodeFactory->new;

# ONE STASH HOLDS `$x` AND `@x` AS UNRELATED VARIABLES, and `$_` vs `@_` is the
# case that bites -- the same collision the stash-key work hit earlier: a key
# spelled without its sigil bound two different variables to one slot.
#
# For a NODE the consequence is sharper than a lookup miss. PadAccess and
# EntryDef are hash-consed by content, so two nodes with the same symbol and no
# sigil ARE THE SAME NODE. The merge is silent and it is wrong.
#
# EntryDef has required this since it was written; PadAccess did not, and the
# chalk session's deserializer now dies rather than invent one. Enforcing it
# only at the consumer makes it a convention; enforcing it at both ends makes
# it a contract.
subtest 'a PadAccess requires its sigil' => sub {
    ok lives { $f->make('PadAccess', targ => 1, sigil => '$', symbol => 'x') },
        'a sigil-carrying PadAccess builds';

    ok !lives { $f->make('PadAccess', targ => 1, symbol => 'x') },
        'one without a sigil dies rather than guessing';
    like $@, qr/sigil/, '... naming what is missing';
};

subtest 'an EntryDef requires its sigil' => sub {
    ok lives {
        $f->make('EntryDef', package => 'main', sigil => '$', symbol => 'g')
    }, 'a sigil-carrying EntryDef builds';

    ok !lives { $f->make('EntryDef', package => 'main', symbol => 'g') },
        'one without a sigil dies rather than guessing';
};

# THE COLLISION THE REQUIREMENT PREVENTS. Without a sigil these two are one
# node; with it they are two. This is the assertion that would have caught a
# regression, rather than merely checking a die fires.
subtest '$_ and @_ are different nodes' => sub {
    my $scalar = $f->make('PadAccess', targ => 1, sigil => '$', symbol => '_');
    my $array  = $f->make('PadAccess', targ => 1, sigil => '@', symbol => '_');

    isnt $scalar->id, $array->id,
        'the sigil keeps $_ and @_ apart in the content hash';
};

# A PAD SLOT WITH NO NAME still needs a sigil, because it is still a node that
# can collide. `$?3` is the synthetic spelling for an unnamed slot.
subtest 'a synthetic pad name still carries a sigil' => sub {
    ok lives {
        $f->make('PadAccess', targ => 3, sigil => '$', symbol => '$?3')
    }, 'a synthetic name builds with a sigil';
};

done_testing;
