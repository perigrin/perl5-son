# ABOUTME: s///e inside a loop body walks its replacement subtree like anywhere else.
# ABOUTME: The loop-body walker lacked the /e recovery the main walker has.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub run_and_wire ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $said = qx{$PERL $file 2>/dev/null};
    my $out  = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    return ($said, $out, $err);
}

# THE REPLACEMENT SUBTREE IS WALKABLE, and the main walker already walks it --
# `s/a/x${p}y/` and `s/(x)/ord $1/e` both lower at the top level. The LOOP-BODY
# walker is a separate function that never got that recovery, so the subtree's
# ops were stepped into with nothing on the stack:
#
#     foreach ($l) { s/(x)/ord $1/e }
#       walked subst -> gvsv -> ord, and `ord` underflowed
#
# It refused rather than crash, which was right -- an internal error is worse
# than a GAP. But the refusal was a missing SITE, not a missing capability:
# one operator implemented in one walker and not the other.
#
# KEYED ON PMf_EVAL, and that narrowing must survive: only the code form has a
# subtree to walk into. Measured -- `s/x/y/` and `s/x/y/g` in a loop were
# always fine, and an earlier version of the refusal took them with it.

# WHAT THIS FIXES is the walker SITE: the replacement subtree is now consumed
# by the shared _walk_subst_replacement instead of being stepped into. A
# self-contained replacement therefore lowers inside a loop, as it always did
# outside one.
subtest 's///e with a self-contained replacement lowers in a loop' => sub {
    # NOT `foreach ($l)`, which aliases $_ to $l so a destructive s/// is an
    # iterator write-back and correctly refuses for that separate reason. This
    # substitutes into a lexical the loop does not alias, which isolates the
    # replacement-subtree walk that was crashing.
    my ($said, $out, $err) = run_and_wire(
        'my $s="axb"; for (1..1) { $s =~ s/x/99/e } print $s;', 'se-loop');
    is $said, 'a99b', 'perl evaluates the replacement' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers';
    like $out, qr/"op"\s*:\s*"RegexSubst"/, '... building a RegexSubst';
};

# TWO THINGS STILL REFUSE, and neither is what this change is about. Recorded
# so the next reader does not mistake them for the crash that was fixed:
#
#   $1 in the replacement -- `s/(x)/ord $1/e` -- refuses with "capture $1 read
#   with no preceding match in scope", the SAME refusal it gets outside a loop:
#   a capture in a replacement refers to the substitution's OWN pattern, which
#   the walker does not model. Pre-existing, and not loop-specific.
#
#   A target that is the aliased iterator (`foreach ($l) { s/x/$n+1/e }`)
#   refuses because the main walker resolves its target through a scope key
#   that is not shared yet. Duplicating that resolution here would repeat the
#   very mistake this change fixes.
# THE TARGET IS RESOLVED, NOT POPPED. `foreach ($l) { s/... }` substitutes into
# the ALIASED ITERATOR -- measured, that subst has targ=0, so its target is $_
# and there is nothing on the stack to take. An earlier version of this fix
# popped a stack value and refused every such loop; the resolver is now shared
# with the main walker, which names $_ the same way.
subtest 's///e on a named lexical inside a loop lowers' => sub {
    my ($said, $out, $err) = run_and_wire(
        'my @a=("axb","cxd"); my $r=""; for my $s (@a) { my $t=$s;'
      . ' $t =~ s/x/9/e; $r.=$t } print $r;', 'se-lexical');
    is $said, 'a9bc9d', 'perl substitutes in each iteration' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers';
};

subtest 's///e on an outer lexical inside a counted loop lowers' => sub {
    my ($said, undef, $err) = run_and_wire(
        'my $s="axb"; for (1..1) { $s =~ s/x/9/e } print $s;', 'se-counted');
    is $said, 'a9b', 'perl substitutes once' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers';
};

# A SUBST INTO THE ALIASED ITERATOR WORKS NOW, and it took two fixes. The loop
# walker's subst arm was gated on PMf_EVAL, so a plain s/// fell through to the
# generic dispatch and became a bogus `Call(builtin, "subst")` over the
# replacement string; and `foreach ($l)` wraps $l in a synthetic one-element
# ArrayLiteral, so the write-back stored into that wrapper instead of rebinding
# $l. Measured, both forms now read a computed node rather than the pre-loop
# constant.
subtest 'a subst into the aliased iterator reaches the source' => sub {
    for my $case (
        [ 'my $l="axb"; foreach ($l) { s/x/y/ } print $l;'          => 'ayb'   ],
        [ 'my $l="axb"; foreach ($l) { s/(x)/ord $1/e } print $l;'  => 'a120b' ],
    ) {
        my ($src, $want) = $case->@*;
        my ($said, undef, $err) = run_and_wire($src, 'se-it' . length($src));
        is $said, $want, "perl gives $want";
        unlike $err, qr/GAP|INTERNAL/, '... and it lowers';
    }
};

# THE UNDERFLOW MUST NOT RETURN. It was an INTERNAL error masked as a silent
# skip -- the worst outcome -- and the refusal existed to convert it. Whatever
# happens to the lowering, this must never crash again.
subtest 'it never underflows the stack' => sub {
    for my $src (
        'my $l="axb"; foreach ($l) { s/(x)/ord $1/e } print $l;',
        'my $l="axb"; foreach ($l) { s/(x)/ord $1/ge } print $l;',
    ) {
        my (undef, undef, $err) = run_and_wire($src, 'se-crash' . length($src));
        unlike $err, qr/Stack underflow|INTERNAL/,
            'no underflow, no internal error';
    }
};

# THE PLAIN FORMS MUST KEEP WORKING -- but not the `foreach ($l)` spelling,
# which was MISCOMPILING: it printed the pre-loop constant, because the
# iterator is an alias and no store-back was emitted. Those now refuse (see
# t/wire-internal-errors-refuse.t).
#
# What must keep working is a subst into a BODY LEXICAL, which is what the
# refusal is keyed narrowly enough to allow -- on the subst's own target, not
# on "a subst exists in this body". An earlier version of that guard took this
# case with it.
subtest 'a substitution into a body lexical is unaffected' => sub {
    for my $case (
        [ 'my @a=("axb"); for my $s (@a) { my $t=$s; $t =~ s/x/y/; print $t }'
          => 'ayb' ],
        [ 'my @a=("axax"); for my $s (@a) { my $t=$s; $t =~ s/x/y/g; print $t }'
          => 'ayay' ],
    ) {
        my ($src, $want) = $case->@*;
        my ($said, undef, $err) = run_and_wire($src, 'se-lex' . length($src));
        is $said, $want, "perl gives $want";
        unlike $err, qr/GAP|INTERNAL/, '... and it lowers';
    }
};

done_testing;
