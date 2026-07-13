# ABOUTME: A method body if/else mutating a field in both arms builds real control flow (zhi 019f5368).
# ABOUTME: The void/discarded form translates; a CONSUMED value-context field-store ternary GAPs, never silently drops the value.

use v5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;
use SoN::Render::Text;

# A branched field mutation (`if(C){$n=$n+5}else{$n=$n+1}`) is the method's
# trailing (discarded) statement: the field stores are the effect, the ternary
# residual is unobserved. It must build real control flow (If/Proj/Region) so
# each arm's field store is control-dependent and a Region merges the arms --
# and it must NOT leave a dead scope-Phi over the arm values (Phi#9), which
# reached the backend with no repr before the fix.
class Counter {
    field $n :param = 0;
    method bump { if ($n < 100) { $n = $n + 5 } else { $n = $n + 1 } }
    method val  { $n }
    # The ternary VALUE is consumed (`my $x = ...; $x`), so the arm residuals are
    # observed -- the consumed value-context field-store shape that must GAP.
    method consumed { my $x = ($n < 100) ? ($n = $n + 5) : ($n = $n + 1); $x }
}

my $renderer = SoN::Render::Text->new();

sub translate_ok ($cv) {
    SoN::OptSuppress::suppress_peep();
    my $graph = SoN::FromOptree->translate($cv);
    SoN::OptSuppress::restore_peep();
    return $graph;
}

sub translate_err ($cv) {
    SoN::OptSuppress::suppress_peep();
    my $err = dies { SoN::FromOptree->translate($cv) };
    SoN::OptSuppress::restore_peep();
    return $err // '';
}

subtest 'a branched field-store method body translates with If/Region and no dead value-Phi' => sub {
    my $graph = translate_ok(\&Counter::bump);
    ok(defined $graph, 'bump translates');
    my $text = $renderer->render($graph);
    like($text, qr/If/,     'has an If node (real control flow, not a pad-rebind merge)');
    like($text, qr/Region/, 'has a Region merging the arms');
    like($text, qr/Assign/, 'has the field-store Assign(s)');

    # The dead scope-Phi regression: before the fix, the TARGMY field write
    # defined the field targ in pad scope, so merge() built a value-Phi over the
    # two arm Add results -- a Phi consumed by nothing, carrying no repr. Assert
    # no Phi merges two Add nodes (the arm residuals). A memory-Phi or a genuine
    # value merge would be fine; a Phi over the arithmetic residuals is the bug.
    for my $node ($graph->nodes->@*) {
        next unless $node->operation eq 'Phi';
        my @arm_ops = map { $_->can('operation') ? $_->operation : '' } $node->inputs->@*;
        my $adds = grep { $_ eq 'Add' } @arm_ops;
        ok($adds < 2, 'no Phi merges two Add residuals (the dead scope-Phi is gone)')
            or diag("Phi merges: @arm_ops");
    }
};

subtest 'a CONSUMED value-context field-store ternary GAPs, never silently drops the value' => sub {
    # `my $x = ($n<100) ? ($n=$n+5) : ($n=$n+1); $x` -- the ternary VALUE is used.
    # The arm residuals are unstamped field-read arithmetic, so a merged ternary
    # would silently be Undef ($x would read undef, not the assigned value). GAP
    # loudly instead of miscompiling (GAP-not-miscompile).
    my $err = translate_err(\&Counter::consumed);
    like($err, qr/^GAP:/, 'consumed value-context field-store ternary GAPs loudly')
        or diag($err);
    like($err, qr/consumed value-context ternary/,
        'the GAP names the consumed-field-store shape');
};

done_testing();
