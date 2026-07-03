# ABOUTME: Tests SoN JSON round-trip of loop graphs: the loop Phi back-edge is a
# ABOUTME: forward reference in any serialization order and must be defer-patched.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;
use SoN::Serialize::JSON;

# Graph::nodes deliberately cuts the loop-Phi back-edge in its topological
# order, so the serialized JSON contains one forward input reference per loop
# Phi. from_json must construct the Phi with its init input and wire inputs[1]
# via set_backedge once every node exists -- the same defer-patch the Chalk
# loader performs. A single-pass resolve yields undef and dies in the use-def
# ADJUST ("Can't call method consumers on an undefined value").

SoN::OptSuppress::suppress_peep();
my $cv = eval 'sub { my $n = 3; my $s = 0; while ($n > 0) { $s += $n; $n-- } $s }';
my $err = $@;
SoN::OptSuppress::restore_peep();
die "compile failed: $err" if $err;

my $graph = SoN::FromOptree->translate($cv);
my $json  = SoN::Serialize::JSON::to_json({ 'main::f' => $graph });

my $loaded = SoN::Serialize::JSON::from_json($json);
my $g = $loaded->{'main::f'};
ok(defined $g, 'loop graph round-trips through to_json/from_json');

my @phis = grep { $_->operation eq 'Phi' } $g->nodes->@*;
is(scalar @phis, 2, 'both loop Phis survive the round-trip');
for my $phi (@phis) {
    ok(defined $phi->inputs->[1],
        'Phi back-edge is wired, not undef (defer-patched)');
    like($phi->inputs->[1]->operation, qr/^(Add|Subtract)$/,
        'back-edge is the loop-carried computation');
    ok((grep { $_ == $phi } $phi->inputs->[1]->consumers->@*),
        'the back-edge value lists the Phi as a consumer');
}

done_testing();
