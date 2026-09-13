# ABOUTME: Every node naming a variable decomposes it the same way: sigil, symbol, package.
# ABOUTME: perl's own terms -- Symbol::qualify turns "symbol names" into qualified "variable names".

use v5.42.0;
use Test2::V0;

use SoN::IR::NodeFactory;

# PERL'S OWN TERMINOLOGY, from Symbol.pm:
#
#     "Symbol::qualify turns unqualified SYMBOL NAMES into qualified VARIABLE
#      NAMES (e.g. "myvar" -> "MyPackage::myvar")"
#
# so the bare identifier is the SYMBOL and the qualified form is the VARIABLE
# NAME. Note `qualify("x")` returns "main::x" -- NO SIGIL either way, because
# the symbol table is sigil-free: the sigil selects a SLOT WITHIN the glob,
# which is why $x and @x share one symbol-table entry.
#
# Three parts, then, and each node that names a variable should spell them the
# same way:
#
#     @        sigil     the glob slot selector
#     a        symbol    perl's word for the bare identifier
#     main     package   perl's word; `stash` is the C-level name for it
#
# WHY IT MATTERS rather than being tidiness: PadAccess carried the whole thing
# as one blob (`varname` => '@a'), which forced every consumer to re-parse it.
# Two hand-rolled parsers of the same string existed in different modules --
# `substr($target->varname, 0, 1)` in the producer to get the sigil, and
# `s/\A[\@\%]//` in the deparse emitter to strip it back off. EntryDef already
# decomposed correctly, so the repo had two conventions for one concept.

my $f = SoN::IR::NodeFactory->new;

subtest 'a lexical names its parts' => sub {
    my $n = $f->make('PadAccess', targ => 1, sigil => '@', symbol => 'a');
    is $n->sigil,  '@', 'sigil';
    is $n->symbol, 'a', 'symbol -- the bare identifier, no sigil';
};

subtest 'a package variable names its parts' => sub {
    my $n = $f->make('EntryDef',
        package => 'main', sigil => '$', symbol => 'g');
    is $n->sigil,   '$',    'sigil';
    is $n->symbol,  'g',    'symbol';
    is $n->package, 'main', 'package -- perl says package, not stash';
};

subtest 'a pad-bound aggregate names its parts' => sub {
    my $c = $f->make('Constant', const_type => 'integer', value => '1');
    for my $case (['ArrayLiteral', '@'], ['HashLiteral', '%']) {
        my ($kind, $sigil) = $case->@*;
        my $n = $f->make($kind, inputs => [$c],
            sigil => $sigil, symbol => 'a');
        is $n->sigil,  $sigil, "$kind sigil";
        is $n->symbol, 'a',    "$kind symbol";
    }
};

# AN ANONYMOUS AGGREGATE NAMES NOTHING, and must not be forced to.
subtest 'an anonymous aggregate has no parts' => sub {
    my $c = $f->make('Constant', const_type => 'integer', value => '1');
    my $n = $f->make('ArrayLiteral', inputs => [$c]);
    ok !defined $n->symbol, 'no symbol';
    ok !defined $n->sigil,  'no sigil';
};

done_testing;
