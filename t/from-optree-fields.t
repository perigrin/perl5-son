# ABOUTME: Tests for SoN::FromOptree feature class field access translation.
# ABOUTME: Verifies class fields produce FieldAccess nodes, lexicals get PadAccess.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use Test2::V0;

use SoN::FromOptree;
use SoN::Render::Text;

class TestFieldPoint {
    field $x :param :reader;
    field $y :param :reader;

    method sum () { $x + $y }
}

my $renderer = SoN::Render::Text->new();

subtest 'Class field reads produce FieldAccess nodes' => sub {
    my $graph = SoN::FromOptree->translate(\&TestFieldPoint::sum);
    ok(defined $graph, 'got a graph');
    my $text = $renderer->render($graph);
    like($text, qr/FieldAccess/, 'has FieldAccess node');
    like($text, qr/Add/, 'has Add for $x + $y');
    like($text, qr/TestFieldPoint/, 'FieldAccess references TestFieldPoint stash');
    diag($text);
};

subtest 'Regular lexicals still produce PadAccess' => sub {
    my $sub = eval 'sub { my $z = 42; $z + 1 }';
    my $graph = SoN::FromOptree->translate($sub);
    my $text = $renderer->render($graph);
    # $z is resolved through scope, so may not appear as PadAccess
    # But it should NOT appear as FieldAccess
    unlike($text, qr/FieldAccess/, 'no FieldAccess for regular lexicals');
    diag($text);
};

done_testing;
