# ABOUTME: A package array/hash (@x, %h) must be refused, never modeled as the
# ABOUTME: stash-NAME string Constant the gv handler pushes.

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
# `gv` pushes a global's NAME as a string Constant (it is the callee name for an
# entersub). `rv2sv` pops that Constant and replaces it with a StashAccess for a
# package SCALAR -- but nothing did so for an AGGREGATE, so the name string was
# left on the stack and flowed into whatever consumed the array.
#
# The consequence was a SILENT MISCOMPILE, measured against perl:
#
#     $#x   became   Length(Constant("x"))   -- the length of the NAME
#
#   @x unset        perl -1   chalk 1
#   @x 1 element    perl  0   chalk 1
#   @x 2 elements   perl  1   chalk 1   <-- agrees, by coincidence
#
# It answered 1 for every package array. The only agreeing case is a 2-element
# array, which is exactly what t/base/term.t's $#x check uses -- so that test
# would have passed while the feature was entirely broken. A test asserting one
# array length could not have caught this; the lengths must DISAGREE.
# ---------------------------------------------------------------------------

# The bare `@x` of t/base/lex.t needs an explicit package name here because this
# file runs under strict; the gv NAME the producer sees is the same either way,
# so the shape under test is unchanged.
subtest 'a package array is refused, not silently mismodeled' => sub {
    my $err = dies { graph_of('sub { $#main::x }') };
    like($err, qr/GAP:/, '$#x on a package array is refused');
    like($err, qr{package array/hash}, '... naming the unmodeled construct');
};

subtest 'a package hash is refused' => sub {
    my $err = dies { graph_of('sub { my %h; $main::pkghash{a} }') };
    like($err, qr/GAP:/, 'a package hash read is refused');
};

subtest 'the NAME string never reaches a Length' => sub {
    # The specific shape of the miscompile: if this ever lowers again, it must
    # measure the ARRAY, never a Constant. A Length over a string Constant is
    # the bug, restated structurally.
    my $err = dies { graph_of('sub { $#main::somepkgarray }') };
    ok($err, 'still refused') or return;
    unlike($err, qr/Length\(Constant/, 'refused before any such node is built');
};

subtest 'LEXICAL aggregates are untouched' => sub {
    # The guard must not catch `my @a` / `my %h`, which are correctly modeled.
    my $g = graph_of('sub { my @a = (1,2,3); $#a }');
    ok(defined $g, 'a lexical array still translates');
    ok(scalar(nodes_of($g, 'Length')), 'and still measures a real Length');

    ok(defined graph_of('sub { my %h = (a => 1); $h{a} }'),
        'a lexical hash still translates');
};

subtest '@_ and %ENV stay exempt (they have real sources)' => sub {
    # @_ resolves via _args_source (a StashAccess for *main::_) and %ENV is
    # pushed fully qualified as main::ENV; both are modeled, so neither may be
    # swept up by the guard.
    ok(defined graph_of('sub { my ($a, $b) = @_; $a }'),
        '@_ destructuring still translates');
    ok(defined graph_of('sub { shift }'),
        'bare shift over @_ still translates');
    ok(defined graph_of('sub { $ENV{PATH} }'),
        '%ENV read still translates');
};

done_testing;
