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
like $list, qr/^ratchet\b.*no rule broken but by the violations held by name/m, q(every rule is hard (stage 10));
# (stage 3's downgrade proof compared the v1 writer with the commit before
# it; the v1 writer is gone. What is left of v1 is SoN::Wire::as_v1, the
# deparser's reader: its round trip over the corpus holds it.)
like $list, qr/^ratchet\b.*corpus-roundtrip\.pl.*ROUNDTRIP >= 430.*EMITS_INVALID_PERL 0/m, "and the deparser's round trip";
unlike $list, qr/downgrade|wire 1/,                                     'no v1 left in it';
# (stage 9b's proof, against the scouts' wire of 006b485, was run once and is
# recorded in the baseline note, section 15: retired in stage 10)
unlike $list, qr/braun/i,                                               "stage 9b's one-time proof is retired";
like $list, qr/^ratchet\b.*chalk's lib.*no wire dropped/m,             "chalk's lib, and a dropped wire fails";

done_testing;
