# Plan: regexes as graphs

Goal (perigrin, 2026-11-11): a constant regex is lowered by chalk into
Sea-of-Nodes (byte loads, compares, branches, a start-offset loop, Phis for
position and captures) and T2 lowers that graph like any other code. No
runtime regex engine; no regex emitter in T2. Scope = every feature chalk's
own lib/ and t/ use (the census); not all of perl's engine yet.

## Census (item 1)

`script/regex-census.pl [DIR...]` (default `lib t`); `--rows FILE...` gives
one row per regex. It reads what PERL compiled (B backend
`script/lib/B/RegexCensus.pm`, `-MO=RegexCensus`, i.e. `perl -c`): escapes,
classes and constant `\Q..\E` are perl's own reading. A constant `\Q..\E` is
applied while perl parses -- nothing left for us; only `\Q$var\E` survives
(a `quotemeta` under the `regcomp` op). "built at run time" = the op has a
`regcomp` kid (an interpolated variable). ~23s for both trees (4 jobs).
Test: chalk `t/bootstrap/regex/regex-census.t`.

Table, 2026-11-11 (count of regexes, files):

```
== lib: 194 files, 900 regexes (match 698, qr 8, split 29, subst 165)
   470     9 files  \A \z \Z
   433    10 files  alternation
   408    11 files  non-capture
   190    16 files  ^ anchor
   183    17 files  quant * + ?
   143    15 files  class [ ]
   124    13 files  \d \w \s
   103    14 files  group ( )
   101    11 files  flag /g
    95    14 files  $ anchor
    47    12 files  . any
    26     9 files  flag /r
    25     9 files  quantified group
    20     8 files  built at run time
    17     4 files  \b \B
    17     3 files  flag /s
     7     3 files  \G
     7     3 files  flag /c
     6     3 files  \Q of a variable
     4     4 files  flag /e
     3     3 files  counted {n,m}
     3     1 files  flag /x
     3     3 files  lazy
     1     1 files  flag /i
     1     1 files  flag /m
     1     1 files  lookahead
     1     1 files  lookbehind
== t: 903 files, 2065 regexes (match 620, qr 1113, split 50, subst 278, trans 4); 4 helper files did not compile alone (t/bootstrap/lib/Test{XS,Perl}Helpers.pm, PrecedenceSpecHelpers.pm, t/fixtures/ir-audit-corpus.pl)
   593   146 files  quant * + ?
   486   141 files  \d \w \s
   291   154 files  flag /g
   283   130 files  ^ anchor
   230   124 files  alternation
   200    87 files  . any
   166    41 files  flag /i
   164    50 files  \b \B
   151    55 files  $ anchor
   151    51 files  group ( )
   132    40 files  class [ ]
    92    76 files  flag /m
    72    54 files  non-capture
    61    26 files  flag /s
    60    32 files  flag /r
    47    24 files  built at run time
    33    28 files  \A \z \Z
    21    11 files  quantified group
    20    14 files  lookahead
    18    16 files  lazy
    17    13 files  \Q of a variable
    14     9 files  lookbehind
     4     2 files  tr
     3     2 files  flag /x
     2     2 files  counted {n,m}
     1     1 files  flag /e
     1     1 files  posix [:alpha:]
```

- IN SCOPE (used): everything above. Notably alternation, (?:), \A\z, ^ $,
  classes, \d\w\s, captures, quantified groups (46), \b, /g /i /m /s /r /c /e
  /x, \G (the lexer), lookahead/lookbehind (t only, 1 in lib), lazy, counted,
  posix class (1), tr (4), split by regex, \Q of a variable (23).
- BUILT AT RUN TIME: 67 (lib 20, t 47) -- item 6 decides how many fold.
- OUT (used nowhere): named captures, backreferences, \p{..} \N, \h \v \R \X
  \K, recursion, (?|..), atomic (?>..), possessive, inline (?i) mods, code
  blocks (0 in chalk itself; the existing support stays).
  (An earlier PPI-based grep counted "possessive" and \h-family uses: false
  positives of reading source text.)

## Item 2: G6's front half moved out of Context

`lib/Chalk/Regex/Pattern.pm`: `compile($pattern, $flags)` -> atoms,
`without_inert_u`, `escape_byte`, `code_block_end` -- moved verbatim (renamed)
from Context (~315 lines out). Context calls `Chalk::Regex::Pattern::compile`.
Test: `t/bootstrap/regex/pattern-parses-to-atoms.t`. G6 refuses today:
alternation, quantified groups, \b, any flag, (?..) but (?: and (?{, mid
^ $, \D\W\S in a class, lazy (as "double quantifier").

## Item 3: a constant regex is its own graph (T2)

- `lib/Chalk/Regex/Graph.pm` `matcher($pattern, $flags)` -> B::SoN-shaped
  wire for `sub { my ($s) = @_; ...; return found ? [start, end, g1s, g1e,..] : undef }`
  (a small structured SSA builder: while_/if_ make Loop/If/Proj/Region and
  phis; trivial loop phis pruned). Loaded by the one loader
  (`_deserialize_graph`), made a `Chalk::MOP::Sub`, lowered by T2's `func()`
  like any sub. T2: `regex_result` calls it where the match is (memo key
  `rx<addr>`, so arms/loops scope it); RegexMatch = defined(result).
- Shape: structured backtracking, no early exits (T2 refuses those):
  `while (found < 0 && start <= len) { SEQ(0, start); start++ }`; a
  quantified single-char atom counts its greedy run then backs off in a
  `while (found < 0 && n >= min)` loop. Characters via substr($s, p, 1) and
  string compares (StrEq/StrGe/StrLe); every position read is <= length.
- CAPTURES: B::SoN ties RegexCapture to its match. Perl's $1 is the LAST
  SUCCESSFUL match's, so T2 reads it only where that match is known to have
  succeeded -- an If's true arm or a ?:'s (an `unless`'s else arm), tracked
  in `$b->{rx_ok}` (`_rx_arm`); elsewhere refused by name ("a capture read
  where its match may have failed").
- `$& $\` $' $+ @- @+` and `$1` as EntryDef: B::SoN gives them as package
  variables of no match -> refused by name at the top of `_value` ("the match
  variable"). Producer work, later: tie them to the match like RegexCapture.
- /u: under graph => 1 the `u` flag is dropped; \d \w \s classes are marked
  `ascii` and the matcher first scans the subject: a byte past ASCII STOPS
  (STDERR message, exit 255) -- perl's /u rules there are Unicode's. T2 is a
  byte machine: it already refuses length/lc/uc when a string CONSTANT goes
  past ASCII (`past_ascii`), so the graph must not hold one (compare with
  "\x7f", not "\x80"). Tests feed non-ASCII through %ENV (TapDiff inherits it).
- Pattern.pm `graph => 1` also takes \A (start), \z (anchored_end 'z', the
  very end) and \Z (= $); without it they stay refused (Context unchanged).
- Probes: chalk `t/bootstrap/regex/t2-a-regex-is-a-graph.t` (18 patterns x
  subjects, captures, refusals, /u stop).

## Items 4-6: the state machine, the ops, interpolation (2026-11-11)

- ONE GENERATOR, rewritten: `Chalk::Regex::Parse` (pattern -> tree: seq, alt,
  group, quant (greedy/lazy, {n,m}), set, assert (^ $ \A \z \Z \b \B \G,
  /m forms), look (ahead/behind, fixed width), rlit) and
  `Chalk::Regex::Graph` (tree -> a small PROGRAM: set, split, jmp, save,
  check, assert, look/lookend, rlit, match -> ONE graph per pattern: a loop
  over pc with a binary if-tree dispatch, a backtrack stack (array of
  pairs: (pc,pos) choices, (-1-K,old) slot restores, look barriers)). The
  nested-loop generator of item 3 is gone; same probes, all green.
  - Empty loops: a body that may match empty gets a progress mark (save
    mark; check mark) -- `(?:a*)*` ends.
  - /i: ASCII letters both cases; /s: `.` any; /x: blanks and #comments;
    posix classes; \d \w \s, /i, posix are ASCII here: a subject with a
    byte past ASCII STOPS (exit 255) -- perl's rules there are Unicode's.
  - Refused by name (census: used nowhere): backrefs, named captures,
    possessive, atomic, \p \h \v \R \X \K \N, (?|..), inline (?i), a
    capture in a negative lookaround, a lookbehind of no one width,
    {n,m} past 64 copies.
- FLAVORS (one graph per pattern AND use): scalar, gscalar (m//g scalar:
  args from, noempty), list, all (m//g list), subst ([new, count]; /g;
  `replacement` $N or a computed one), split (perl's rules: limit, awk ' ',
  /^/ = /^/m, captures, no empty match at a field start or the end), and
  `translit` (tr: [new, count]; /c /d /s refused).
- T2: regex_result / regex_list / regex_subst / regex_split / translit;
  qr_value (a hash blessed Regexp: `pattern` (perl's (?^flags:pat)
  string) and `matcher` -- a code value of the graph's wrapper; QrMatch
  calls it at run time; a value of no class Regexp stops: "a pattern built
  at run time"); t2_ref_str prints a Regexp as its pattern.
- CONTEXT (B::SoN stamps a match Boolean whatever its context): a match is a
  list where print takes it (even through B::SoN's Coerce), a list's element,
  a sub call's or push/join/sprintf/die/warn's argument, a list assignment's
  right side; RETURNED it is refused (its caller's context).
- s/// and tr IN PLACE only when pinned AND of a PadAccess (`my` scalar
  kept here): Store of the new string (and pos reset). Pinned of a VALUE
  (B::SoN folded `(my $t = $s) =~ s///`'s copy) or /r or floating: the node's
  value is the new string. RegexSubstCount: count or "" (s///); tr's count
  is a number (0 too).
- pos(): two allocas per variable (pos, where the last /g match was empty),
  undef at entry; t2_pos_update after each m//g (reset on a miss unless /c);
  reset by any store to the variable (assign, s///, tr); `pos($s) = N`
  stores. Only for a `my` scalar kept in memory: a variable T2 never stores
  is a folded value (a scalar /g on one: refused).
- Captures: read only where their match succeeded: an If's true arm, a ?:'s,
  an `unless`'s else, a LOOP BODY whose condition is the match, and an If's
  merge-phi inputs made in that arm. $& $` $' $+ @- @+ refused ("the match
  variable": B::SoN reads them as package variables of no match).
- INTERPOLATION (item 6): `_pattern_parts` folds what B::SoN folded to
  constants (strings, Concat, quotemeta of a constant); `\Q$x\E` of a value
  known only at run time is a RLIT: a placeholder (U+FDD0+k) in the pattern,
  an argument of the graph, matched as `substr($s, pos, length) eq lit`.
  Refused: a quantifier straight after it, /i with it. `_made_a_string`:
  refuse at compile time where what makes the pattern is a string (EnvRead,
  Concat, a string builtin) -- NOT by stamp (B::SoN stamps Test::Chalk's
  passed qr `Str`).
- Census of run-time-built patterns (script tags them): 68 (lib 20, t 48):
  23 `\Q of a variable` -> rlit; 44 `interpolates a variable` -> compile
  where B::SoN folded the variable to a constant, or it is a whole qr value
  (QrMatch); a qr interpolated into a bigger pattern, or a string from input,
  stays a named GAP ("a pattern built at run time").

## Producer bugs found by this goal

- FIXED: `my $ok = $s =~ $re ? 1 : 0` -- the match took every value above an
  enclosing list's still-open mark as pattern parts (pattern = "$got-ternary
  . $s . $re": Test::Chalk's like). Parts only where the regcomp's kid is a
  list beginning with pushmark (as qr already asked). t/wire-a-match-takes-
  only-its-own-pattern.t.
- OPEN: `s/(\d)/<$1>/g` -- B::SoN computes a computed replacement ONCE (from
  its own /g match): T2 refuses an s///g with a computed replacement.
- OPEN: `split /\Q$v\E/` and any interpolated split pattern: B::SoN GAP
  (T2 takes the pattern's parts when it is given).
- OPEN: `"ab" =~ /$p/` (a constant subject, interpolated pattern): B::SoN
  internal error (StackSim underflow).
- OPEN: `while (1) { ... last }` with if/elsif arms: B::SoN GAP.

## Item 7: measured (2026-11-11)

- CENSUS COMPILES: every constant regex in chalk's lib/ (947 of 947) and t/
  (2025 of 2025, after [:ascii:]) builds its graph (Chalk::Regex::Graph, by the
  flavor T2 would use). Not counted: 67 built at run time (above), 4 tr.
- Test::Chalk like/unlike: Test::More's bytes through T2 (with flags too) --
  the named GAP of milestone 2 is closed. It took a PRODUCER fix (the match's
  pattern took a stray mark's values).
- Corpus T2 gate-green 202 -> 213 (floor raised); census 412/0/0.
- Lessons:
  - A refusal by STAMP is a guess: B::SoN stamps a passed qr `Str` where it
    is also joined to a string. Refuse by what MAKES the value.
  - List context is by consumer AND by input slot: a statement after a pinned
    match takes it as its MEMORY input (`join` after `$s =~ /b/g`), which is
    no list context.
  - Tests that pinned the fallback's shape (Coerce[Boolean->Str], "not T2")
    were retargeted to perl's answer + "T2's" -- after checking T2's answer
    equals perl's for each.

### Chalk's test files with Test::Chalk (2026-11-12)

The 396 files are the 279 easy tier plus 117 that use like/unlike. Each runs as
a copy with `use Test::More` swapped for Test::Chalk, then TapDiff compares
perl with T2. The tool is `swap-one.pl`, 240s a file.
- SAME 0, DIFFERS 0, REFUSED 99, TIMEOUT 297.
  - TIMEOUT means over 240s OR no output (crash); see
    a-sweeps-absence-is-not-evidence.md. It is the compile-cost wall of
    milestone 2: each file follows ~130 modules.
- REFUSED top causes: a scalar deref of a reference T2 doesn't make 32,
  a method call with no invocant 21, a string eval with a lexical in scope 19,
  a direct call with no sub 7, `local` on a package array or hash 5,
  from_json refused in its module 3, a statement `require` 3.
- Regex-related: 1. The producer GAP "s///ge on a subject that is not a plain
  scalar variable", a named refusal. No refusal comes from Chalk::Regex or T2's matcher.
- Next lever, not regexes: compile cost. Link on demand before DCE, plus the
  per-module cache (decision-wire-format-sereal.md). The cache pays within ONE
  sweep: 396 files share the same ~130 modules.

## Closing check (2026-11-12): each item's evidence

Census, recounted over every file (one `--rows` per file):
- Run-time-built patterns: 69 (lib 20, t 49). This is the goal's 69; the
  table's 67/68 above came from runs before this goal's own tests added theirs.
- 22 are `\Q` of a variable: an rlit, which compiles.
- 2 are a whole qr value (Test::Chalk's `$s =~ $re`): QrMatch, which compiles.
- At most 45 interpolate a variable into a bigger pattern. That is the named
  GAP "a pattern built at run time", except where B::SoN folds the variable to
  a constant.

Item 4, one probe file per feature (chalk t/bootstrap/regex/; each compares
with perl and failed first):

| feature | probes |
|---|---|
| alternation, (?:..), \b \B, /i /m /s /x, lazy, lookahead, lookbehind, posix | t2-regex-features.t |
| possessive, atomic, backrefs, named, \p.. | t2-regex-features.t (REFUSED BY NAME) |
| non-ASCII under \d\w\s, /i, posix: stop, exit 255 | t2-a-regex-is-a-graph.t, t2-regex-features.t |
| \Q..\E (constant; a variable: rlit) | t2-regex-quotemeta.t |

Item 5, the ops:

| op | probes |
|---|---|
| m// scalar, captures | t2-a-regex-is-a-graph.t |
| m//g list, list context | t2-regex-list.t |
| /g scalar + pos(), /gc + \G | t2-regex-pos.t |
| s/// /g /r, in place or a value | t2-regex-subst.t |
| s///e, s///er | t2-regex-subst.t (added 2026-11-12: already SAME, pinned) |
| s///ge (a replacement per match) | REFUSED by name: B::SoN computes it once (producer, open) |
| split | t2-regex-split.t |
| tr/// (/r; /c /d /s refused) | t2-regex-tr.t |
| qr values, like/unlike | t2-regex-qr.t, test-chalk-gives-test-more-s-tap.t |
| (?{ }) code blocks | t2-regex-code-block.t (2026-11-12) |

Code blocks through T2 (were refused): Parse reads `(?{..})` as a zero-width
`code` node. T2 passes each body B::SoN lifted (CODE_GRAPHS) to the matcher
as a code value (CodeOfFn). The graph calls them in order on the hit
(`accept`). This happens only where perl's optimizer finds the whole text
first: an all-literal pattern (groups allowed, no flags) in scalar context.
Anywhere else, how often a block runs is the optimizer's, so it is REFUSED by
name ("how often it runs is perl's optimizer's"), as Context did.

Open producer bugs above are each a named refusal or GAP, never a wrong
answer.
- Lesson (found by verify, not by my new test): a match whose code blocks run
  is a STORE. B::SoN pins it as a memory version, and a read of the version
  before it must be made before it (`reads_before` over `passed`). Without
  that, `my $u = $t + 1` between two block-running matches read the second
  block's value: "10 11" for "10 2". The old Context-path test
  (llvm-a-regex-code-block-runs-where-matching-passes.t) caught it. Probe a new
  feature with the old feature's tests too, not only your own.
- Lesson 2 (verify's probes): a matcher made WITHOUT the bodies (a qr value
  matched elsewhere, a qr interpolated into a pattern) silently ran no block
  once Parse accepted them. That was 7 new WRONG probes. Graph now refuses
  unless the caller passes one body for each block (`codes`). When the reader
  learns a construct, every builder that reads it must agree on what it needs.

Failing-first, shown after the fact (2026-11-12): today's ten t2-regex
probe files were run against chalk BEFORE this goal (cfa6154b, the parent of
72a2acbb). 159 of 180 assertions FAIL there. Every feature's SAME-with-perl
probe fails, because T2 then had no regex at all. The 21 that pass are "not
DIFFERS / refused by name" checks, which hold either way.
- a-regex-is-a-graph 33/38, features 32/37, list 15/16, pos 9/9, qr 20/21,
  quotemeta 5/6, split 13/14, subst 14/15, tr 5/8, code-block 13/16.
Item 7's like/unlike: test-chalk-gives-test-more-s-tap.t ('like and unlike',
'like with flags') is SAME with Test::More's bytes through T2, in the suite.
