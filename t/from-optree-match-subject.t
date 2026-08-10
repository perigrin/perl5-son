# ABOUTME: A match takes its subject from a pad target, the stack (OPf_STACKED),
# ABOUTME: or $_ — never from the op's targ unconditionally.

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

sub nodes_of ($g, $op) { grep { $_->operation eq $op } $g->nodes->@* }

# ---------------------------------------------------------------------------
# The subject of a match reaches the op three ways, and only ONE of them is the
# op's pad target (measured, perl 5.42):
#
#   $s =~ /re/   lexical subject IS the pad target      targ=1  flags=0x02
#   $g =~ /re/   package subject is PUSHED              targ=0  flags=0x46
#   /re/         unbound: the subject is $_             targ=0  flags=0x02
#
# Reading targ unconditionally gave the two targ-less forms a fabricated read of
# pad slot 0, emitted as PadAccess(varname: "$?0") — a name that belongs to no
# variable. That node reached the LLVM backend unstamped and GAPped there, so
# the failure LOOKED like a missing type. It was not: stamping it would have
# compiled a match against an uninitialized slot, turning a loud refusal into a
# silent wrong answer.
# ---------------------------------------------------------------------------

subtest 'an unbound match reads $_ as the package scalar main::_' => sub {
    my $g = translate('sub { $_ = "test"; /^test/ ? 1 : 0 }');

    my @pads = nodes_of($g, 'PadAccess');
    is(scalar @pads, 0, 'no PadAccess is fabricated for the missing subject')
        or diag('varnames: ' . join(',', map { $_->varname // '(undef)' } @pads));

    my ($match) = nodes_of($g, 'RegexMatch');
    ok($match, 'the match node exists');
    my $subject = $match->inputs->[0];
    is($subject->operation, 'StashAccess', 'its subject is a StashAccess');
    is($subject->stash_name, 'main', '... in package main');
    is($subject->var_name,   '_',    '... naming $_');
};

subtest 'the $_ read and the $_ store are ONE node' => sub {
    my $g = translate('sub { $_ = "test"; /^test/ ? 1 : 0 }');

    # This is what makes the match observe the store. Two separate StashAccess
    # nodes for the same variable would read a location nothing had written.
    my @stash = nodes_of($g, 'StashAccess');
    is(scalar @stash, 1, 'exactly one StashAccess node for $_');

    my ($match)  = nodes_of($g, 'RegexMatch');
    my ($assign) = nodes_of($g, 'Assign');
    ok($assign, 'the store exists');
    is($match->inputs->[0], $assign->inputs->[0],
        'the match subject and the assign lvalue are the same node (hash-consed)');
};

subtest 'a package-scalar subject is popped from the stack (OPf_STACKED)' => sub {
    my $g = translate('sub { our $pkgsubj = "test"; $pkgsubj =~ /^test/ ? 1 : 0 }');

    is(scalar nodes_of($g, 'PadAccess'), 0, 'no fabricated PadAccess');

    my ($match) = nodes_of($g, 'RegexMatch');
    my $subject = $match->inputs->[0];
    is($subject->operation, 'StashAccess', 'the pushed subject is the StashAccess');
    is($subject->var_name, 'pkgsubj', '... naming the package scalar, not slot 0');
};

subtest 'a lexical subject still comes from the pad target' => sub {
    my $g = translate('sub { my $s = "test"; $s =~ /^test/ ? 1 : 0 }');

    my ($match) = nodes_of($g, 'RegexMatch');
    my $subject = $match->inputs->[0];
    isnt($subject->operation, 'StashAccess',
        'a lexical subject is NOT rerouted to a package scalar');
};

subtest 'a runtime pattern on a pushed subject GAPs rather than guessing' => sub {
    # Both the subject and the matcher are on the stack; the pop order has not
    # been established, and guessing it is how the two get silently swapped.
    my $err = dies { translate('sub { our $ps = "x"; my $re = qr/x/; $ps =~ $re ? 1 : 0 }') };
    like($err, qr/GAP:/, 'it refuses loudly');
    like($err, qr/pushed subject/, '... naming the shape it will not lower');
};

done_testing;
