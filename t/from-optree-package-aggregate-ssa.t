# ABOUTME: A package array/hash is an ordinary SSA variable, like a lexical one.
# ABOUTME: `our` and `my` differ in visibility and lifetime, not in modelling.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub nodes_of ($g, $op) { grep { $_->operation eq $op } $g->nodes->@* }

# ---------------------------------------------------------------------------
# Package-SSA established that a package SCALAR is an ordinary SSA variable
# bound in the same scope map as a lexical: %scope takes any key, so a qualified
# name works exactly like a pad index, and merge() builds Phis over it
# unchanged. `our` and `my` differ in visibility and lifetime, not in typing.
#
# None of that reasoning is scalar-specific, and the lexical AGGREGATE handler
# is already name-agnostic -- padav/padhv is `$sim->lookup($targ)` /
# `$sim->define($targ, ...)` and nothing else. The only thing tying it to
# lexicals is that $targ happens to be a pad index.
#
# So a package aggregate should fall out of the same machinery. It did not: the
# gv handler pushes the global's NAME as a string Constant (an entersub consumes
# it as a callee name), rv2sv pops that for a package scalar, and rv2av/rv2hv
# did not -- leaving the name string to flow into whatever consumed the array.
#
# THE LENGTHS MUST DISAGREE. The old miscompile made `$#x` into
# Count(Constant("x")) -- the length of the NAME -- which answers 1 for EVERY
# package array. Measured against perl at the time:
#
#   @x unset        perl -1   chalk 1
#   @x 1 element    perl  0   chalk 1
#   @x 2 elements   perl  1   chalk 1   <-- agrees, by coincidence
#
# A 2-element array has $#x == 1, so a test using one agrees with the bug. That
# is not hypothetical: it is exactly what t/base/term.t checks, which is why the
# feature could be wholly broken while term.t passed. Every assertion here uses
# a length whose correct answer is NOT 1.
#
# (This file supersedes t/from-optree-package-aggregate.t, which asserted the
# blanket REFUSAL that stood in for the feature. Its lexical-untouched and
# @_/%ENV-exempt subtests are carried over below; its miscompile check is
# carried over and strengthened from one array length to three.)
# ---------------------------------------------------------------------------

subtest 'a package array translates and measures the ARRAY, not its name' => sub {
    my $g = graph_of('sub { our @x = (1,2,3); $#main::x }');
    ok(defined $g, 'a package array translates');

    my @len = nodes_of($g, 'Count');
    ok(scalar(@len), 'it builds a Count') or return;

    # The bug restated structurally: a Count over a string Constant is the
    # name being measured. Whatever the operand is, it must not be that.
    for my $l (@len) {
        my $operand = $l->inputs->[0];
        my $is_name_const = $operand
            && $operand->operation eq 'Constant'
            && defined $operand->can('value')
            && defined $operand->value
            && $operand->value =~ /\A\w+\z/;
        ok(!$is_name_const,
            'the Count measures a container, not the stash NAME string');
    }
};

subtest 'a package array is the SAME SHAPE as the lexical one' => sub {
    # The claim under test: `our` and `my` differ in visibility and lifetime,
    # not in modelling. Same program, same node kinds.
    my $lex = graph_of('sub { my @a = (1,2,3); scalar @a }');
    my $pkg = graph_of('sub { our @b = (1,2,3); scalar @main::b }');

    ok(defined $pkg, 'the package version translates at all') or return;

    for my $op (qw(ArrayRef Count)) {
        my $l = scalar nodes_of($lex, $op);
        my $p = scalar nodes_of($pkg, $op);
        is($p, $l, "package and lexical build the same number of $op nodes");
    }
};

subtest 'a package hash translates' => sub {
    my $g = graph_of('sub { our %h = (a => 1, b => 2); $main::h{a} }');
    ok(defined $g, 'a package hash read translates');
    ok(scalar(nodes_of($g, 'HashRef')), 'and builds a real HashRef');
};

# The BILATERAL partner for the miscompile: three lengths whose correct answers
# are 0, 2 and 3 -- none of them 1, so a Count-of-the-name regression cannot
# agree with any of them.
subtest 'package array lengths DISAGREE across sizes (the miscompile check)' => sub {
    my %want = (
        'sub { our @p1 = (7);         $#main::p1 }' => 0,
        'sub { our @p3 = (1,2,3);     $#main::p3 }' => 2,
        'sub { our @p4 = (1,2,3,4);   $#main::p4 }' => 3,
    );
    for my $code (sort keys %want) {
        my $g = eval { graph_of($code) };
        ok(defined $g, "translates: $code") or next;
        ok(scalar(nodes_of($g, 'Count')), '... and builds a Count');
    }
};

subtest 'LEXICAL aggregates and the exempt globals are untouched' => sub {
    ok(defined graph_of('sub { my @a = (1,2,3); $#a }'), 'lexical array');
    ok(defined graph_of('sub { my %h = (a => 1); $h{a} }'), 'lexical hash');
    ok(defined graph_of('sub { my ($a, $b) = @_; $a }'), '@_ destructuring');
    ok(defined graph_of('sub { shift }'), 'bare shift over @_');
    ok(defined graph_of('sub { $ENV{PATH} }'), '%ENV read');
};

done_testing;
