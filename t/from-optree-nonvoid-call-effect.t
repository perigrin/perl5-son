# ABOUTME: A non-void direct-sub Call must still get a control_in pin so it
# ABOUTME: stays reachable and ordered; only the void guard decided push vs. pin before.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# Translate a code string under rpeep suppression (the production -MO=SoN path)
# and return the graph, or die on GAP/compile error.
sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $cerr = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $cerr" if $cerr;
    return SoN::FromOptree->translate($cv);
}

sub calls_named ($g, $name) {
    return grep {
        $_->operation eq 'Call' && ($_->name // '') eq $name
    } $g->nodes->@*;
}

# F4: `sub f { print "x"; 2 } my $r = f(); 3` -- f() is called in NON-void
# (scalar-assignment) context. Before this fix, _handle_entersub only pinned
# control_in `if $void`; a non-void Call got no control pin at all, so it was
# unreachable from Return and the producer's reachability walk dropped it
# entirely.
subtest 'non-void direct call has a defined control_in and stays in the graph' => sub {
    my $g = translate('sub f { print "x"; 2 } sub { my $r = f(); 3 }');
    my ($call) = calls_named($g, 'main::f');
    ok(defined $call, 'the f() Call node is present in the graph')
        or diag('ops = [' . join(' ', map { $_->operation } $g->nodes->@*) . ']');
    ok(defined $call->control_in,
        'the non-void f() Call has a defined control_in (not dropped)');
};

done_testing();
