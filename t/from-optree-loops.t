# ABOUTME: Tests for SoN::FromOptree loop handling.
# ABOUTME: Verifies loop translation produces Loop + Phi structures.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;
use SoN::Render::Text;

my $renderer = SoN::Render::Text->new();

subtest 'Simple arithmetic without loops still works' => sub {
    my ($graph, $text) = _translate(eval 'sub { my $x = 0; my $y = 10; $x + $y }');
    like($text, qr/Start/, 'has Start');
    like($text, qr/Return/, 'has Return');
    diag($text);
};

subtest 'While loop produces Loop node' => sub {
    my ($graph, $text) = _translate(eval 'sub { my $i = 0; while ($i < 10) { $i = $i + 1 } $i }');
    like($text, qr/Loop/, 'has Loop node');
    unlike($text, qr/If/, 'no If -- the Loop IS the header (corpus contract)');
    like($text, qr/NumLt/, 'has less-than comparison');
    like($text, qr/Region/, 'has the exit Region');
    diag($text);
};

subtest 'While loop has Phi for modified variable' => sub {
    my ($graph, $text) = _translate(eval 'sub { my $i = 0; while ($i < 10) { $i = $i + 1 } $i }');
    like($text, qr/Phi/, 'has Phi for loop-carried variable');
    diag($text);
};

subtest 'foreach over a range lowers as a counted loop' => sub {
    # Per corpus control-flow.md D3: foreach my $i (1..3) desugars to a
    # counted loop -- induction Phi (init low, step +1), continuation
    # condition NumGt(high+1, i_phi), and the same Loop/Proj/Region skeleton
    # as while. No Iter/Range node exists in the contract.
    my $graph = SoN::FromOptree->translate(
        eval 'sub { my $s = 0; foreach my $i (1..3) { $s += $i } $s }');
    my @nodes = $graph->nodes->@*;
    my ($loop) = grep { $_->operation eq 'Loop' } @nodes;
    ok(defined $loop, 'has a Loop node');
    ok(!(grep { $_->operation eq 'If' } @nodes), 'no If in the header');

    my @phis = grep { $_->operation eq 'Phi' } @nodes;
    is(scalar @phis, 2, 'two Phis: induction $i and carried $s');
    my ($i_phi) = grep { ($_->inputs->[0]->value // '') == 1 } @phis;
    my ($s_phi) = grep { ($_->inputs->[0]->value // '') == 0 } @phis;
    ok(defined $i_phi, 'induction Phi init is the range low (1)');
    ok(defined $s_phi, 'carried Phi init is 0');

    my $step = $i_phi->inputs->[1];
    is($step->operation, 'Add', 'induction step is an Add');
    is($step->inputs->[0]->id, $i_phi->id, 'step reads the induction Phi');
    is($step->inputs->[1]->value, 1, 'step is +1');

    my $sum = $s_phi->inputs->[1];
    is($sum->operation, 'Add', '$s backedge is the body sum');
    is([sort map { $_->id } $sum->inputs->@*],
       [sort ($s_phi->id, $i_phi->id)],
       'body sum reads both Phis');

    my ($cmp) = grep { $_->operation eq 'NumGt' } @nodes;
    ok(defined $cmp, 'has the continuation condition');
    is($cmp && $cmp->inputs->[0]->value, 4, 'condition bound is high+1 (4)');
    is($cmp && $cmp->inputs->[1]->id, $i_phi->id, 'condition reads the induction Phi');

    my ($ret) = grep { $_->operation eq 'Return' } @nodes;
    is($ret->inputs->[0]->operation, 'Region', 'Return control is the exit Region');
    is($ret->inputs->[1]->id, $s_phi->id, 'Return value is the $s Phi');
};

subtest 'foreach over a general list still refuses loudly' => sub {
    # Only the range form (OPf_STACKED enteriter, two constant bounds) is
    # lowered; a general list iteration has no counted-loop desugaring yet.
    like(
        dies {
            SoN::FromOptree->translate(
                eval 'sub { my $s = 0; for my $i (1, 2, 5) { $s = $s + $i } $s }')
        },
        qr/GAP/,
        'list foreach dies with a GAP message'
    );
};

sub _translate ($sub) {
    my $graph = SoN::FromOptree->translate($sub);
    my $text = $renderer->render($graph);
    return ($graph, $text);
}

done_testing;
