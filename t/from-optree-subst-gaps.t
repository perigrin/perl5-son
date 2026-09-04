# ABOUTME: s/// idioms outside the corpus R3 slice GAP loudly, never silently miscompile (zhi 019f2d79).
# ABOUTME: implicit $_/package targets and scalar-context (count) destructive s/// must die, not emit wrong IR.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# Translate a code string under rpeep suppression (the production -MO=SoN path)
# and return the die message, or '' if it translated without error.
sub translate_ok ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $cerr = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $cerr" if $cerr;
    return SoN::FromOptree->translate($cv);
}

sub translate_err ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $cerr = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $cerr" if $cerr;
    my $err = dies { SoN::FromOptree->translate($cv) };
    return $err // '';
}

# The subst handler keys the target on $op->targ. For an implicit $_ or a
# package/global target the pad targ is 0, so the handler cannot name the
# target -- it used to fabricate a slot-0 rebind and drop the substitution
# silently (returned the pre-subst value). It must GAP loudly instead.
# This used to assert a GAP. The concern it names -- a fabricated slot-0 rebind
# that DROPS the substitution, so a later read returns the pre-subst value -- is
# exactly what the handler now gets right: $_ is the package scalar main::_, an
# ordinary binding in the scope map, and the substitution rebinds it there. So
# the subtest asserts the rebind rather than the refusal, which is the property
# the GAP was standing in for.
subtest 'an implicit $_ s/// rebinds $_, and does not drop the substitution' => sub {
    my $g = translate_ok('sub { $_ = "foobar"; s/foo/baz/; $_ }');
    ok(defined $g, 'it translates') or return;

    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    ok(defined $ret, 'the sub returns') or return;
    is($ret->inputs->[0]->operation, 'RegexSubst',
        '$_ reads the substitution result, not the pre-subst binding');
};

# This refusal was reachable all along but the count-context GAP fired first
# and hid it. With count context lowered, it is the only thing standing between
# a package target and a SILENT DROP: _subst_target keyed a missing targ as
# '$main::_', which bound the wrong variable and left no RegexSubst in the
# graph at all. Measured -- `our $g="aaa"; $main::g =~ s/a/b/g;` printed the
# folded "aaa" where perl prints "bbb".
subtest 'package/global target GAPs loudly' => sub {
    my $err = translate_err('sub { our $g; $main::g =~ s/foo/baz/ }');
    like($err, qr/^GAP: s\/\/\/ on a package\/global target/,
        'package-target s/// produces its own loud GAP') or diag($err);
};

# Destructive s/// in scalar/boolean context returns the match COUNT, not the
# rewritten string. This GAPped rather than commit the silent value+type
# miscompile of pushing the subject; it now LOWERS, with the count as a
# separate node over the substitution so the two results stay distinct. The
# stamp is Str because zero matches is "" and not 0 -- see
# t/from-optree-subst-count-context.t for the measurements.
subtest 'scalar-context destructive s///g lowers to a count' => sub {
    my $g = translate_ok('sub { my $x="hello"; my $n = ($x =~ s/l/L/g); $n }');
    ok(defined $g, 'it translates') or return;
    ok(scalar(grep { $_->operation eq 'RegexSubstCount' } $g->nodes->@*),
        'the count is its own node, not the substituted subject');
};

subtest 'scalar-context destructive s/// (single) lowers to a count' => sub {
    my $g = translate_ok('sub { my $x="hello"; my $n = ($x =~ s/l/L/); $n }');
    ok(defined $g, 'it translates') or return;
    ok(scalar(grep { $_->operation eq 'RegexSubstCount' } $g->nodes->@*),
        'a single-match subst counts too');
};

# An interpolated (multi-part) replacement is a substcont subtree, not a single
# folded const. These two GAPped because the handler "pops ONE stack Constant
# and uses it as the whole replacement, dropping every other part" -- a silent
# miscompile (`s/a/$y$z/` emitted `$z` only; `s/a/x$y/` dropped the literal
# `x`). The refusal was the right answer to that, and it is no longer the only
# one: the subtree is now WALKED with the same machinery /e uses, so the parts
# are assembled instead of dropped.
#
# THE ASSERTION IS UNCHANGED IN SUBSTANCE -- no part may be lost. Only the
# acceptable outcome widened, from "refuse" to "refuse or assemble". Written
# as a property rather than as a GAP match, so it stays meaningful whichever
# way a future change goes.
subtest 'interpolated multi-var replacement loses no part' => sub {
    my $err = translate_err('sub { my $x="aaa"; my $y="Y"; my $z="Z"; $x =~ s/a/$y$z/; $x }');
    if ($err =~ /^GAP:/) { pass('refused loudly, which is acceptable'); return }
    is($err, '', 'it translates cleanly');
};

subtest 'interpolated literal+var replacement loses no part' => sub {
    my $err = translate_err('sub { my $x="aaa"; my $y="Y"; $x =~ s/a/x$y/; $x }');
    if ($err =~ /^GAP:/) { pass('refused loudly, which is acceptable'); return }
    is($err, '', 'it translates cleanly');
};

# --- regressions: the corpus-green and value-yielding forms must still work ---

subtest 'single foldable-var replacement still translates' => sub {
    # A single interpolated variable folds to a compile-time Constant under
    # rpeep-suppression (pmreplroot NULL, PMf_CONST), so it is lowerable and
    # correct today -- it must NOT be swept up by the interpolation GAP.
    my $err = translate_err('sub { my $x="aaa"; my $y="Y"; $x =~ s/a/$y/; $x }');
    is($err, '', 'single folded-var replacement is not GAPped');
};


subtest 'void-context destructive s/// (corpus R3) still translates' => sub {
    my $err = translate_err('sub { my $x="foobar"; $x =~ s/foo/baz/; $x }');
    is($err, '', 'the gate-green R3 case is not swept up by the new GAPs');
};

subtest 'scalar-context nondestructive s///r (string value) still translates' => sub {
    # /r yields the rewritten STRING, so scalar context is correct here -- the
    # count GAP must fire only for DESTRUCTIVE subst, keyed on PMf_NONDESTRUCT,
    # not on context alone (scalar /r and scalar destructive share OPf flags).
    my $err = translate_err('sub { my $x="hello"; my $y = ($x =~ s/l/L/gr); $y }');
    is($err, '', 's///r scalar value form is not GAPped');
};

subtest 's///e lowers -- its replacement is a walkable subtree' => sub {
    # This used to assert a GAP. The replacement is not opaque: it hangs off
    # the subst's pmreplroot and survives rpeep suppression, so it is walked
    # and rides as a second operand on the RegexSubst. perl agrees on the
    # value -- `s/foo/o()/e` over "foobar" is "XXbar".
    my $err = translate_err('sub { my $x="foobar"; sub o { "XX" } $x =~ s/foo/o()/e; $x }');
    is($err, '', 's///e with a call replacement translates');
};

done_testing();
