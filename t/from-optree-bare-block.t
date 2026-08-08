# ABOUTME: A bare block `{ ... }` compiles to enterloop with nextop==lastop
# ABOUTME: (no back edge); it must translate straight-line, never GAP or drop statements.

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

sub prints ($g) {
    return grep { $_->operation eq 'Print' } $g->nodes->@*;
}

# Walk backward from Return along control predecessors, collecting every node
# on the real control graph. A node merely PRESENT in the hash-consed graph is
# not enough proof -- it must be reachable from Return this way, or it is dead
# (unreachable) code. Most nodes have a single predecessor via control_in;
# a Region (control-merge point, e.g. after an if/else) has none and instead
# carries its predecessors in inputs, so both must be walked.
sub control_chain_ops ($g) {
    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    my @ops;
    my @stack = ($ret);
    my %seen;
    while (my $n = pop @stack) {
        next unless defined $n && !$seen{$n}++;
        push @ops, $n->operation;
        if (defined(my $ci = $n->control_in)) {
            push @stack, $ci;
        }
        elsif ($n->operation eq 'Region') {
            push @stack, $n->inputs->@*;
        }
    }
    return @ops;
}

# A bare block compiles to enterloop(next->leaveloop last->leaveloop) --
# nextop==lastop, i.e. no back edge -- unlike a real while loop where
# nextop is `unstack` and lastop is the loop's tail. FromOptree.pm:567
# used to route EVERY enterloop into _translate_while_loop, which reads an
# `and`/`or` inside the block as the loop's header condition and strands the
# block's own statements as unreachable loop body wired onto the loop-body
# Proj (index 0) instead of the control chain leading to Return -- a silent
# miscompile: only the code AFTER the block survived.
subtest 'a bare block with an if-modifier statement keeps both prints reachable' => sub {
    my $g = translate(
        'sub { my $c=0; { print "first\n" if $c; print "after\n"; } print "end\n"; 1 }');
    my @p = prints($g);
    is(scalar @p, 3, 'all three Print nodes exist in the graph')
        or diag('ops = [' . join(' ', map { $_->operation } $g->nodes->@*) . ']');

    my @chain = control_chain_ops($g);
    is(scalar(grep { $_ eq 'Print' } @chain), 3,
        'all three prints are reachable on the control chain from Return')
        or diag('control chain = [' . join(' ', @chain) . ']');
    ok(!(grep { $_ eq 'Loop' } @chain),
        'no spurious Loop node on the control chain for a back-edge-less block');
};

subtest 'package Foo { ... } bare block translates without GAPing' => sub {
    my $g = translate('sub { package Foo { print "in\n" } 1 }');
    my @p = prints($g);
    is(scalar @p, 1, 'the print inside the package block survives')
        or diag('ops = [' . join(' ', map { $_->operation } $g->nodes->@*) . ']');
};

done_testing;
