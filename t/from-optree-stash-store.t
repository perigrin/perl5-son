# ABOUTME: A package-scalar assignment is a store on the memory chain, not a typed slot:
# ABOUTME: a later read is at the LAST store's version, whatever representation it stored.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN;
use SoN::FromOptree;

# `our $g = 5` binds a value that later reads of $g resolve to. It used to emit
# an Assign(EntryDef-lvalue, value) into a TYPED module-level slot, with one
# slot kind per representation (i64 / (ptr,len) / double).
#
# That model gave the hash-consed lvalue node ONE representation while each
# assignment carried its own, so a scalar assigned two types lost the second
# store entirely -- `our $g = 1; $g = "hi"; print $g` printed 1. Package scalars
# are now bound in the same scope map as lexicals, which is why the lexical path
# never had that bug: `our` and `my` differ in visibility and lifetime, not in
# typing.

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

# THE READ IS THROUGH MEMORY, NOT THE BINDING. These bodies store the scalar
# they read, so it is a written package scalar (_package_scalars_written) and
# its read is an EntryDef at the store's version -- never the stored Constant
# forwarded. The tests used to see the Constant, and only because the write
# scan did not read an anon sub's body: a named sub with the same text has
# always read through memory. stored_at($read) is the value of the store the
# read is versioned by.
sub stored_at ($read) {
    return undef unless $read->operation eq 'EntryDef';
    my ($w) = grep { ref $_ && $_->operation eq 'EntryWrite' } $read->inputs->@*;
    return $w ? $w->inputs->[1] : undef;
}

sub nodes_of ($g, $op) { grep { $_->operation eq $op } $g->nodes->@* }
sub return_of ($g)     { (grep { $_->operation eq 'Return' } $g->nodes->@*)[0] }

subtest 'a read is at the store, not a slot load' => sub {
    my $g = graph_of('sub { our $g = 5; $g }');
    my $val = stored_at( return_of($g)->inputs->[-1] );
    ok($val, 'the Return value is a read at the store\'s version') or return;
    is($val->operation, 'Constant', 'the store it reads holds the assigned value');
    is($val->value, 5, '... which is what was assigned');

    is(scalar nodes_of($g, 'Assign'), 0,
        'no Assign(EntryDef-lvalue): an assignment is a definition, not a store');
};

subtest 'a second store is a new version — the read sees the LATER value' => sub {
    my $g = graph_of('sub { our $g = 5; $g = 7; $g }');
    my $val = stored_at( return_of($g)->inputs->[-1] );
    ok($val, 'the read is at a store\'s version') or return;
    is($val->value, 7, 'the read is at the second store, not the first')
        or diag('a dropped second store is the miscompile this pins');
};

subtest 'a definition may change representation — the bug the slot model had' => sub {
    # One hash-consed lvalue node could carry only one representation, so the
    # second definition here wrote a slot family no read loaded from and was
    # silently lost. Each store carries its own value, of its own type.
    my $g = graph_of('sub { our $g = 1; $g = "hi"; $g }');
    my $val = stored_at( return_of($g)->inputs->[-1] );
    ok($val, 'the read is at a store\'s version') or return;
    is($val->operation, 'Constant', 'the store it reads holds a value');
    is($val->value, 'hi', 'the Str store wins, not the earlier Int')
        or diag('this returned 1 under the typed-slot model');

    my $g2 = graph_of('sub { our $g = "hi"; $g = 7; $g }');
    my $val2 = stored_at( return_of($g2)->inputs->[-1] );
    is($val2 && $val2->value, 7, 'and in the other direction');
};

subtest 'an UNBOUND read is the entry definition' => sub {
    # A package scalar read before any assignment in this unit has no reaching
    # definition here; the EntryDef names its incoming value. This is the one
    # role EntryDef keeps.
    my $g = graph_of('sub { our $neverset; $neverset }');
    my ($sa) = nodes_of($g, 'EntryDef');
    ok(defined $sa, 'the entry definition is a EntryDef') or return;
    is($sa->package, 'main', 'stash is main');
    is($sa->symbol, 'neverset', 'named for the variable');
};

subtest 'a lexical is unaffected' => sub {
    my $g = graph_of('sub { my $x = 5; $x = 7; $x }');
    is(return_of($g)->inputs->[-1]->value, 7,
        'the lexical path still resolves to the latest definition');
};

done_testing();
