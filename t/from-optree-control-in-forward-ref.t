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
use JSON::PP ();

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
# serializer (SoN::Serialize::JSON), then checks the WIRE for the defect
# directly.
#
# IT USED TO LOAD THE WIRE BACK through a vendored copy of chalk's loader, and
# asserted the control chain survived the round trip. That copy is gone (it was
# chalk's code, 1334 lines, never loaded by anything in lib/), and loading is
# not what this test needs: a forward reference is a property OF THE JSON --
# an id referenced by a node at position i whose own entry is at position j > i.
# Reading positions is what a strictly-in-order loader does, so checking them
# on the wire tests the same defect at its source, in this repo's own contract,
# without carrying a consumer to do it.
# =============================================================================
subtest 'void method call (inc) survives FromOptree -> wire, with no forward ref' => sub {
    my $g = canonical_graph(
        'sub { my $c = Counter->new(n => 10); $c->inc; $c->val }');

    my ($inc) = grep { $_->operation eq 'Call' && $_->name eq 'inc' } $g->nodes->@*;
    ok(defined $inc, 'producer-side graph has a Call(inc)') or return;

    my $json = SoN::Serialize::JSON::to_json({ 'main::corpus_case' => $g });
    my $data = JSON::PP::decode_json($json);
    my @nodes = ( $data->{methods}{'main::corpus_case'}{nodes} // [] )->@*;
    ok(scalar @nodes, 'the graph reached the wire') or return;

    # Position of every node id in emission order -- what an in-order loader
    # would have available as it builds each entry.
    my %pos;
    $pos{ $nodes[$_]{id} } = $_ for 0 .. $#nodes;

    my ($ret_i) = grep { $nodes[$_]{op} eq 'Return' } 0 .. $#nodes;
    ok(defined $ret_i, 'the wire has a Return') or return;
    my $ctrl = $nodes[$ret_i]{control_in};
    ok(defined $ctrl, q{Return carries a control_in on the wire}) or return;
    ok(exists $pos{$ctrl}, 'its control_in names a node that is actually emitted')
        or return;

    # THE DEFECT, stated as the wire property: no control_in may point FORWARD.
    # A loader that builds nodes in array order resolves such a reference to
    # undef and silently drops whatever it named.
    my @forward = grep {
        defined $nodes[$_]{control_in}
            && defined $pos{ $nodes[$_]{control_in} }
            && $pos{ $nodes[$_]{control_in} } > $_
    } 0 .. $#nodes;
    is(scalar @forward, 0, 'no control_in is a forward reference')
        or diag('forward at node positions: ' . join(', ', @forward));

    # AND THE VOID CALL IS STILL REACHABLE, which is what the forward ref would
    # have cost. Walk the control chain the way a loader would, by id.
    my %by_id = map { $_->{id} => $_ } @nodes;
    my (@chain, %seen);
    my $c = $ctrl;
    while (defined $c && !$seen{$c}++) {
        my $n = $by_id{$c} or last;
        push @chain, $n;
        $c = $n->{control_in};
    }
    my ($inc_in_chain) = grep {
        $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'inc'
    } @chain;
    ok(defined $inc_in_chain,
        'the void inc() Call is reachable along the wire control chain (not dropped)');
};

done_testing();
