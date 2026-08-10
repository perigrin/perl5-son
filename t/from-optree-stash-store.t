# ABOUTME: A package-scalar assignment is an SSA DEFINITION, not a store into a slot:
# ABOUTME: later reads resolve to the bound value, and a rebind is simply a new binding.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# `our $g = 5` binds a value that later reads of $g resolve to. It used to emit
# an Assign(StashAccess-lvalue, value) into a TYPED module-level slot, with one
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

sub nodes_of ($g, $op) { grep { $_->operation eq $op } $g->nodes->@* }
sub return_of ($g)     { (grep { $_->operation eq 'Return' } $g->nodes->@*)[0] }

subtest 'a read resolves to the bound value, not a slot load' => sub {
    my $g = graph_of('sub { our $g = 5; $g }');
    my $val = return_of($g)->inputs->[-1];
    is($val->operation, 'Constant', 'the Return value is the bound value');
    is($val->value, 5, '... which is what was assigned');

    is(scalar nodes_of($g, 'Assign'), 0,
        'no Assign(StashAccess-lvalue): an assignment is a definition, not a store');
};

subtest 'a rebind is a new binding — the read sees the LATER value' => sub {
    my $g = graph_of('sub { our $g = 5; $g = 7; $g }');
    my $val = return_of($g)->inputs->[-1];
    is($val->value, 7, 'the read resolves to the second definition, not the first')
        or diag('a dropped rebind is the miscompile this pins');
};

subtest 'a definition may change representation — the bug the slot model had' => sub {
    # One hash-consed lvalue node could carry only one representation, so the
    # second definition here wrote a slot family no read loaded from and was
    # silently lost. Under SSA each definition simply has its own.
    my $g = graph_of('sub { our $g = 1; $g = "hi"; $g }');
    my $val = return_of($g)->inputs->[-1];
    is($val->operation, 'Constant', 'the read resolves to a value');
    is($val->value, 'hi', 'the Str definition wins, not the earlier Int')
        or diag('this returned 1 under the typed-slot model');

    my $g2 = graph_of('sub { our $g = "hi"; $g = 7; $g }');
    is(return_of($g2)->inputs->[-1]->value, 7, 'and in the other direction');
};

subtest 'an UNBOUND read is the entry definition' => sub {
    # A package scalar read before any assignment in this unit has no reaching
    # definition here; the StashAccess names its incoming value. This is the one
    # role StashAccess keeps.
    my $g = graph_of('sub { our $neverset; $neverset }');
    my ($sa) = nodes_of($g, 'StashAccess');
    ok(defined $sa, 'the entry definition is a StashAccess') or return;
    is($sa->stash_name, 'main', 'stash is main');
    is($sa->var_name, 'neverset', 'named for the variable');
};

subtest 'a lexical is unaffected' => sub {
    my $g = graph_of('sub { my $x = 5; $x = 7; $x }');
    is(return_of($g)->inputs->[-1]->value, 7,
        'the lexical path still resolves to the latest definition');
};

done_testing();
