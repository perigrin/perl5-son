# ABOUTME: Regression test for the from_json `classes` branch: a classful payload
# ABOUTME: must load, keep its field-type inference, and return an undef MOP.

use v5.42.0;
use Test2::V0;
use File::Temp ();

use SoN::IR::Serialize::JSON ();

# ---------------------------------------------------------------------------
# REGRESSION (son-ir-divorce, 2026-08-01). The trim issue replaced the whole
# tail of from_json's `classes` branch with a loud die, on the theory that the
# branch existed only to replay a MOP this repo does not vendor. It does NOT:
# the branch runs _infer_param_field_types, _stamp_field_access_reprs,
# _seed_and_propagate_reprs and the ADJUST-store inference FIRST. The die
# therefore computed all of that, threw it away, and aborted — and no test
# drove a classful payload through from_json, so nothing went red.
#
# Only the _replay_classes call (the $mop producer) was genuinely dead. $mop is
# undef here by design: perl5-son is the PRODUCER side and never consumes it.
#
# These assertions are chosen to fail if the branch is ever skipped OR aborted
# again: the field-type reprs below exist ONLY because the inference ran.
# ---------------------------------------------------------------------------

my $SRC = <<'PERL';
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n = 5;
    method val  { $n }
    method plus { $n + 1 }
}
PERL

my ($fh, $tmp) = File::Temp::tempfile(SUFFIX => '.pl', UNLINK => 1);
print $fh $SRC;
close $fh;

my $json = `$^X -Ilib -MO=SoN,json,package=Counter $tmp 2>/dev/null`;
ok($json =~ /\S/, 'producer emitted JSON for the class')
    or bail_out('no producer output; cannot test the loader');
like($json, qr/"classes"/, 'the payload really carries a classes section')
    or bail_out('payload has no classes section; the branch under test is not reached');

my ($graphs, $mop);
ok(lives { ($graphs, $mop) = SoN::IR::Serialize::JSON::from_json($json) },
    'from_json does not die on a payload with a classes section')
    or diag($@);

ok(defined $graphs && keys %$graphs, 'graphs are returned, not discarded');
is($mop, undef, 'mop is undef — this repo vendors no MOP to replay into');

# The load-bearing half: these reprs are produced by the inference passes that
# the regression computed and threw away. A skipped or aborted branch leaves
# them undef.
subtest 'the classes-branch field-type inference actually ran' => sub {
    my $val = $graphs->{'Counter::val'};
    ok($val, 'Counter::val graph loaded') or return;

    my ($fa) = grep { $_->operation eq 'FieldAccess' } $val->nodes->@*;
    ok($fa, 'Counter::val has a FieldAccess node') or return;
    is($fa->representation, 'Int',
        'FieldAccess carries the field type — _stamp_field_access_reprs ran');

    my $plus = $graphs->{'Counter::plus'};
    ok($plus, 'Counter::plus graph loaded') or return;

    my ($add) = grep { $_->operation eq 'Add' } $plus->nodes->@*;
    ok($add, 'Counter::plus has an Add node') or return;
    is($add->representation, 'Int',
        'the repr propagated past the field read — _seed_and_propagate_reprs ran');
};

done_testing;
