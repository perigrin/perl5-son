---
name: concise-is-a-rendering-not-the-optree
description: "B::Concise drops fields, so two ops that print identically can differ; read the accessor for a flags question"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-26T14:06:08.091Z
---

A `B::Concise` dump is a RENDERING of the optree, not the optree. It omits
fields, so two ops that print byte-for-byte identically can carry different
flags and mean different things.

Measured 2026-09-26 on `split`:

    split / /, "  a b "   4 fields, ["", "", "a", "b"]
    split " ", "  a b "   2 fields, ["a", "b"]        -- awk mode

Both render as the same line:

    5  </> split(/" "/ => @a:1,2)[t2] vK/LVINTRO,ASSIGN,LEX,IMPLIM

The separator is `PMf_SKIPWHITE` (2048) in `pmflags`, which Concise does not
print:

    split / /, ...        pmflags=0
    split " ", ...        pmflags=2048
    my $p=" "; split($p)  pmflags=2048

(So it is a COMPILE-TIME fact even for a runtime pattern: perl sets the bit
whenever the pattern is a plain string expression rather than a `//` literal.)

THREE CONSTRUCTS NOW, all the same shape -- the identity is a BIT, and an
op-name list cannot carry it:

    split " "        PMf_SKIPWHITE (2048) in pmflags   awk mode
    local *v = ...   OPpLVAL_INTRO on rv2gv            save/restore
    local $v = ...   OPpLVAL_INTRO on gvsv             save/restore

`*v = \@A` and `local *v = \"x"` are the SAME OP one bit apart:

    *v = \@A           rv2gv sKRM*/1
    local *v = \"x"    rv2gv sKRM*/LVINTRO,1

Concise DOES print LVINTRO, so this one is visible in a dump -- but it is
absent from any list derived by taking op NAMES, which is how both this project
and pvm's `lintOps` summarise an optree. A construct can need no new ops and
still be a different program.

**Why this matters beyond split:** "measured, the optrees are identical" is a
claim this project makes constantly, and from a Concise diff it only supports
the weaker "identical in what Concise prints." A negative reached that way is
not a negative about the optree.

**How to apply:** Concise is right for op ORDER, op NAMES and the flags it does
render (`s`/`l`/`v` want, `M`/`R`, named private bits). For any question about a
specific flag -- especially `pmflags`, and anything on a PMOP or UNOP_AUX --
read the accessor directly in a `CHECK` block:

    use B;
    CHECK {
        my %seen;
        for (my $x = B::main_start(); $$x && !$seen{$$x}++; $x = $x->next) {
            next unless $x->name eq 'split';
            printf STDERR "pmflags=%s\n", $x->pmflags;
        }
    }

And never write an optree constant from memory --
[[never-write-an-optree-constant-from-memory]] is the same lesson about the
values; this one is about the view.

Related: [[compiling-is-not-running]],
[[verify-the-harness-before-reading-its-output]]
