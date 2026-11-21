# ABOUTME: tools/gates.sh is the one command that runs every gate of the wire v2 plan;
# ABOUTME: this holds its list of gates to the plan's Global constraints.
use v5.42.0;
use Test2::V0;

# THE GATES OF docs/plans/2026-11-20-wire-v2.md, "Global constraints". A gate
# dropped from the script is a gate nobody runs.
my @gates = qw(producer-suite chalk-suite census corpus-gate probes ratchet);

ok -x 'tools/gates.sh', 'tools/gates.sh is there and runs';
my @listed = map { (split ' ')[0] } split /\n/, qx(tools/gates.sh --list 2>&1);
is $?, 0, '--list exits 0';
is [ sort @listed ], [ sort @gates ], '--list names each gate, and no other';

# A LIMIT IS PART OF THE GATE: the census and the corpus gate are numbers.
my $list = qx(tools/gates.sh --list 2>&1);
like $list, qr/^census\b.*ROUNDTRIP >= 426.*DIFFERS 0.*LLI_FAIL 0/m, 'the census limits';
like $list, qr/^corpus-gate\b.*>= 222/m,                              'the corpus gate limit';
like $list, qr/^probes\b.*WRONG 0/m,                                  'the probe limit';
like $list, qr/^ratchet\b.*wire-verify-baseline/m,                    q(the ratchet holds the rows);
# (stage 3's downgrade proof compared the v1 writer with the commit before
# it; the v1 writer is gone. What is left of v1 is SoN::Wire::as_v1, the
# deparser's reader: its round trip over the corpus holds it.)
like $list, qr/^ratchet\b.*corpus-roundtrip\.pl.*ROUNDTRIP >= 430.*EMITS_INVALID_PERL 0/m, "and the deparser's round trip";
unlike $list, qr/downgrade|wire 1/,                                     'no v1 left in it';
like $list, qr/^ratchet\b.*chalk's lib per graph.*no wire dropped/m,   "chalk per graph (perigrin), and a dropped wire fails";

done_testing;
