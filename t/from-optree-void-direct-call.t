# ABOUTME: A void-context direct named-sub call is threaded as a statement effect, not dropped (zhi 019f26a5).
# ABOUTME: Covers the unconditional void call and the statement-modifier-arm (`foo() if $c`) case.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# Translate a code string under rpeep suppression (the production -MO=SoN path)
# and return the graph, or die on GAP.
sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $cerr = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $cerr" if $cerr;
    return SoN::FromOptree->translate($cv);
}

sub ops_of ($g) {
    my %seen;
    return grep { !$seen{$_}++ } map { $_->operation } $g->nodes->@*;
}

sub has_stmt_effect_call ($g) {
    return scalar grep {
        $_->operation eq 'Call' && defined $_->control_in
    } $g->nodes->@*;
}

# The direct-call branch of _handle_entersub always pushed the Call to the
# stack (value context), never threading a VOID call as a statement effect the
# way the method branch does (zhi 019f2dee/019f2df7). So a void direct call was
# dead and silently dropped -- even unconditionally.
subtest 'unconditional void direct call is threaded, not dropped' => sub {
    my $g = translate('sub { my $n = 0; helper(); $n }');
    my @ops = ops_of($g);
    ok((grep { $_ eq 'Call' } @ops), 'the void helper() call survives as a Call node')
        or diag("ops = [@ops]");
    ok(has_stmt_effect_call($g), 'the void Call is a statement effect (control-threaded)');
};

# The statement-modifier-arm case: `helper() if $x > 3` -- the and/or void
# handler must recognize a bare entersub arm (not only a method_named arm) so
# the call becomes control-dependent on the guard instead of vanishing.
subtest 'void direct call in a runtime-conditional arm is threaded' => sub {
    my $g = translate('sub { my $x = shift; my $n = 0; helper() if $x > 3; $n }');
    my @ops = ops_of($g);
    ok((grep { $_ eq 'If' } @ops), 'the guard produces an If branch')
        or diag("ops = [@ops]");
    ok((grep { $_ eq 'Call' } @ops), 'the guarded helper() call survives as a Call node')
        or diag("ops = [@ops]");
};

# --- honest GAPs: forms not lowerable now must die loudly, never drop silently ---

subtest 'nested branch in the arm stays a loud GAP' => sub {
    my $err = dies {
        translate('sub { my $x=shift; my $y=shift; my $n=0; if ($x>3) { helper() if $y>3 } $n }');
    };
    like($err // '', qr/^GAP:/, 'a nested branch inside the arm GAPs, does not silently drop')
        or diag($err);
};

# A void call AND a scalar rebind in the SAME arm needs both control-threading
# (for the call) and a value merge (for the rebind); merge() emits a value-Phi
# the backend cannot place without a memory store. This is 2b-3 mixed-effect
# territory -- GAP loudly rather than emit an unplaceable Phi (adversarial
# verification wf_900ef202 caught this as a GREEN->GAP reachability regression
# when the void-call detection first fired on a pad-rebinding arm).
subtest 'void call + scalar rebind in one arm GAPs loudly (not an unplaceable Phi)' => sub {
    my $err = dies {
        translate('sub { my $x=shift; my $n=0; if ($x>3) { helper(); $n=5 } $n }');
    };
    like($err // '', qr/^GAP:/, 'mixed void-call + rebind arm GAPs') or diag($err);
};

# A PURE void-call arm (no rebind) must still translate -- it is the case this
# fix targets, and the mixed-effect GAP must not sweep it up.
subtest 'pure void-call arm (no rebind) still translates' => sub {
    my $g = translate('sub { my $x=shift; my $n=0; helper() if $x>3; $n }');
    my @ops = ops_of($g);
    ok((grep { $_ eq 'If' } @ops) && (grep { $_ eq 'Call' } @ops),
        'pure void-call arm keeps its If + Call') or diag("ops=[@ops]");
};

done_testing();
