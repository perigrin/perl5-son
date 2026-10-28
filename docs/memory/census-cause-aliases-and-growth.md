# Census cause: a reference to an element of an array that may grow (346 -> 348, pin 485b4d2e)

**Cause:** "a reference to an element of an array that may grow is not
lowered" held 3 cases: 187, 190 and 198.
- 187 and 190 round-trip in probes.
- 198 now hits "dispatch: N::set_stamp has repr=" (a void method's value).

## What changed (chalk only)

- **A foreach alias lives one pass.** `_alias_loop`: the alias
  `\$a[$i]` has an index that is a Loop's counter Phi. Its data readers are
  only TernaryExpr, LocalAlias, or a PostfixDeref that nothing takes a
  reference of. For such an alias, only growth inside that loop's body can
  move it (`_in_loop_body` walks control back to the loop's body Proj).
  Two stores in the body are exempt:
  - a store at constant 0, since a pass over the array means it has an
    element;
  - a store `$a[$i]` whose index is the counter (from 0) of a loop tested
    `@a > $i`, in that loop's body, where nothing pops, shifts or splices
    @a (`_store_bounded_by_its_loop`). This is the producer's
    `$_ = 0 for @a`.
- `_array_may_grow` is now `_array_growths`, which returns the growth
  sites rather than a flag.

## A miscompile found and fixed (pre-existing at pin 368b9bde)

A read through a foreach alias, deferred as a pending tag read at the start
of the pass, was lowered at its use. That is after a later element store
in the same pass, so it read the store:
- `for my $x (@a) { $s .= $x; $a[0] = 0 }` gave 02 for perl's 12;
- `my $y = $x; $a[0] = 9; $s .= $y` gave 92 for 12.

The fix is `_make_pending_reads_before($node)`:
- **Before an element store or an array-mutating call:** each pending
  through-a-reference read (PostfixDeref, Subscript, Count, Exists) is
  made. Where all its readers are TernaryExprs choosing it, the ternary is
  made with its guard kept, frozen, and served from cache (TernaryExpr
  joins the frozen-served ops). Any other pending read is refused by name.
- **Before a Loop or an If:** only the alias ternaries (Exists condition)
  are made. A store in the body would make them there, which does not
  dominate a use after it (lli: "Instruction does not dominate all uses").
- **Skipped:**
  - a read reaching an unlowered loop Phi (another loop's);
  - a read of a named variable (EntryDef, PadAccess), which no element
    store writes;
  - a store to a lexical aggregate nothing takes a reference of
    (`_never_referenced`).

- **Also skipped (check g180 found these):**
  - **The store's own reads.** `$_[0][$_[1]] = $_[0][$_[1]] . "!"` makes
    its RHS before it stores.
  - **Another frame's pending reads.** `_pending_tag_reads` is never
    cleared, so a read left waiting under one inline frame's cache showed
    up at a `shift` in another (pvm 176). Each read records the cache it
    waits under (`_pending_tag_cache`) and is acted on only under that
    cache. A loop body shares its frame's cache, so its alias reads still
    count. A loop's memory Phi is not in the cache, which is why keying
    on the version's cache entry brought the wrong answers back.

## Lessons

- Widening a refusal can uncover a wrong answer the refusal hid. Probe
  the newly allowed shape with a read before and after a store, in the
  same pass.
- The same shape was also reachable without the refusal (a literal array
  and a constant-index store). Check the committed code too, before
  calling it new.
