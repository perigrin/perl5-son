# ABOUTME: s/// idioms outside the corpus R3 slice GAP loudly, never silently miscompile (zhi 019f2d79).
# ABOUTME: implicit $_/package targets and scalar-context (count) destructive s/// must die, not emit wrong IR.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# Translate a code string under rpeep suppression (the production -MO=SoN path)
# and return the die message, or '' if it translated without error.
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
subtest 'implicit $_ target GAPs loudly (was: subst silently dropped)' => sub {
    my $err = translate_err('sub { $_ = "foobar"; s/foo/baz/; $_ }');
    like($err, qr/^GAP:/, 'implicit $_ s/// produces a loud GAP') or diag($err);
    unlike($err, qr/consumers on an undefined|Can.t call method/,
        'not a crash -- a clean GAP');
};

subtest 'package/global target GAPs loudly' => sub {
    my $err = translate_err('sub { our $g; $main::g =~ s/foo/baz/ }');
    like($err, qr/^GAP:/, 'package-target s/// produces a loud GAP') or diag($err);
};

# Destructive s/// in scalar/boolean context returns the integer match COUNT,
# not the rewritten string. The producer stamps every subst result Str and
# pushes the rewritten string -- correct for void context and for /r, wrong
# for scalar-context destructive (a silent value+type miscompile). GAP it.
subtest 'scalar-context destructive s///g (count) GAPs loudly' => sub {
    my $err = translate_err('sub { my $x="hello"; my $n = ($x =~ s/l/L/g); $n }');
    like($err, qr/^GAP:/, 'count-context destructive s/// produces a loud GAP') or diag($err);
};

subtest 'scalar-context destructive s/// (single) GAPs loudly' => sub {
    my $err = translate_err('sub { my $x="hello"; my $n = ($x =~ s/l/L/); $n }');
    like($err, qr/^GAP:/, 'single-match count-context s/// produces a loud GAP') or diag($err);
};

# An interpolated (multi-part) replacement is a substcont subtree, not a single
# folded const. The handler pops ONE stack Constant and uses it as the whole
# replacement, dropping every other part -- a silent miscompile (`s/a/$y$z/`
# emits replacement `$z` only; `s/a/x$y/` drops the literal `x`). GAP loudly on
# any subst whose replacement is a runtime subtree ($op->pmreplroot set).
subtest 'interpolated multi-var replacement GAPs loudly' => sub {
    my $err = translate_err('sub { my $x="aaa"; my $y="Y"; my $z="Z"; $x =~ s/a/$y$z/; $x }');
    like($err, qr/^GAP:/, 'multi-var replacement produces a loud GAP') or diag($err);
};

subtest 'interpolated literal+var replacement GAPs loudly' => sub {
    my $err = translate_err('sub { my $x="aaa"; my $y="Y"; $x =~ s/a/x$y/; $x }');
    like($err, qr/^GAP:/, 'literal-prefix + var replacement produces a loud GAP') or diag($err);
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

subtest 's///e (code replacement) still GAPs (pre-existing)' => sub {
    my $err = translate_err('sub { my $x="foobar"; sub o { "XX" } $x =~ s/foo/o()/e; $x }');
    like($err, qr/^GAP:/, 's///e remains a loud GAP');
};

done_testing();
