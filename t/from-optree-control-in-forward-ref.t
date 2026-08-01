# ABOUTME: End-to-end pin for the void-method-call forward-control-ref bug:
# ABOUTME: `$c->inc; $c->val` must survive FromOptree -> wire JSON -> Chalk load.

use v5.42.0;
use feature 'class';
use Test2::V0;
use B;
no warnings 'experimental::class';

use SoN::OptSuppress;
use SoN::FromOptree;
use SoN::Serialize::JSON ();
use SoN::IR::Serialize::JSON ();

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

# =============================================================================
# THE ROOT CAUSE (`my $c=Counter->new(n=>10); $c->inc; $c->val`):
#
# inc() is a VOID method call whose result is discarded; its only anchor into
# the graph is being the Return's control predecessor (control_in). It has NO
# other consumer. A naive wire encoding puts inc's control_in reference on
# Return's node entry before inc's own array position is guaranteed to
# precede it -- from_json builds nodes strictly in array order, so a genuine
# forward reference resolves to undef, silently dropping inc.
#
# This test drives the REAL producer (SoN::FromOptree) and the REAL wire
# serializer (SoN::Serialize::JSON), then loads through Chalk's loader
# (SoN::IR::Serialize::JSON::from_json) -- the exact cross-repo boundary
# the bug lives on.
# =============================================================================
subtest 'void method call (inc) survives FromOptree -> wire -> Chalk load' => sub {
    my $g = canonical_graph(
        'sub { my $c = Counter->new(n => 10); $c->inc; $c->val }');

    my ($inc) = grep { $_->operation eq 'Call' && $_->name eq 'inc' } $g->nodes->@*;
    ok(defined $inc, 'producer-side graph has a Call(inc)') or return;

    my $json = SoN::Serialize::JSON::to_json({ 'main::corpus_case' => $g });
    my $loaded = SoN::IR::Serialize::JSON::from_json($json);
    ok(exists $loaded->{'main::corpus_case'}, 'graph present after Chalk load') or return;
    my $loaded_graph = $loaded->{'main::corpus_case'};

    my ($loaded_ret) = grep { $_->operation eq 'Return' } $loaded_graph->nodes->@*;
    ok(defined $loaded_ret, 'loaded graph has a Return') or return;

    my $ctrl = $loaded_ret->can('control_in') ? $loaded_ret->control_in : undef;
    ok(defined $ctrl, q{Return's control_in resolved on load (the forward ref survived)})
        or return;

    # Walk the control_in chain from Return looking for the inc() Call -- it
    # may be Return's DIRECT control predecessor, or reached transitively
    # through an intervening control node (e.g. Loop/If/Region), depending on
    # exactly how method-dispatch control threads. Either way it must be
    # found, not silently dropped.
    my @chain;
    my $c = $ctrl;
    my %seen;
    while (defined $c && !$seen{ $c->id }++) {
        push @chain, $c;
        $c = $c->can('control_in') ? $c->control_in : undef;
    }
    my ($inc_in_chain) = grep {
        $_->operation eq 'Call' && $_->can('name') && ($_->name // '') eq 'inc'
    } @chain;
    ok(defined $inc_in_chain,
        'the void inc() Call is reachable via the loaded control_in chain (not dropped)')
        or diag('control chain ops: ' . join(',', map { $_->operation } @chain));

    # It must also be reachable from Graph::nodes() -- what the backend
    # actually walks to decide what gets lowered.
    my ($inc_in_nodes) = grep {
        $_->operation eq 'Call' && $_->can('name') && ($_->name // '') eq 'inc'
    } $loaded_graph->nodes->@*;
    ok(defined $inc_in_nodes,
        'the void inc() Call is reachable from Graph::nodes() on the loaded graph');
};

done_testing();
