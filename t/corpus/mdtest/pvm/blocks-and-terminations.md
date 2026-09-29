# Block-valued expressions, and leaving

`do BLOCK` and `eval BLOCK` both put a BLOCK where an expression goes with
no comma between it and what follows -- a parse fork perl itself resolves
by heuristic, and the one perl gets wrong as an anonymous hash. `die` and
`exit` are the two jumps with no landing site inside the source: `die`
unwinds to the nearest enclosing `entertry` frame, which the source need
not contain at all, and `exit` unwinds past every frame there is. They sit
beside the block pair because `die` is only writable in this tier once
`eval BLOCK` has spelled the frame it unwinds to.

`time` is here for neither reason, and says so: it is not control flow. It
is in this tier because 06 is the EARLIEST tier that can hold it.

**Tier 06 control.** Introduces `cond_expr`, `die`, `enteriter`,
`entertry`, `exit`, `goto`, `iter`, `last`, `leavetry`, `next`, `redo`,
`time`, `unstack`. Depends on 05_scoping.

Every case binds a runtime value and branches on it second.
A constant condition ERASES the construct: measured, `if (1) { print "y" }`
emits `pushmark`, `const` and `print` and no branch op at all, and
`while (0) { print "y" }` emits `enter`, `nextstate` and `leave` -- an
empty program. `$ENV{X}` is unset when the harness runs, so `// N` is a
stable operand the optimiser cannot see through.

## `do BLOCK` in expression position

The value is the block's last statement. It is not an anonymous hash, and
nothing in the token stream says which it is. The other `do BLOCK` case
opens a post-test loop with the same two tokens; the fork is decided by
what FOLLOWS the closing brace, so a parser cannot choose the production
when it reads the `do`.

THE ERASURE COMES FIRST, because it is why this case is shaped the way it
is. Measured, `my $r = do { 1 }; print $r;` emits `enter`, `nextstate`,
`const` and `padsv_store` -- NO OP AT ALL for the construct. `do { 1 }` is
a bare `const`, and a case spelled that way would pass its output test
while measuring nothing whatsoever.

So the block gets a runtime operand and more than one statement -- and
even then the construct adds no op of its own. What survives is an
`enter`/`leave` pair, tier 01's ops, with an `s` flag rather than the `v`
a statement-position block gets, and the LAST statement's value falling
out of the `leave` into the assignment. The block-valued expression is a
FLAG on an op perl already had, which is the same shape tier 03 measures
for scalar versus list context. The INTRODUCES set does not grow, and that
is the honest result.

WHAT THE OUTPUT FALSIFIES. perl disambiguates `{` at the start of a term
by heuristic, and the wrong answer is an anonymous hash -- read that way,
`$r` would hold a REFERENCE and this case would print `HASH(0x...)`. It
prints a scalar. One byte of output separates the two trees.

The `+ 1` is load-bearing twice over: it keeps the last statement
unfoldable, and it makes the printed value differ from the `7` the block's
first statement binds -- so a parser that took the FIRST statement as the
block's value, or that treated the two statements as a comma list and kept
the left one, prints `7` and fails here too.

`ref($r)` would say the same thing more directly and is deliberately not
used: `ref` is tier 08's op and this tier may not reach forward for it.

```perl
my $r = do { my $t = $ENV{X} // 7; $t + 1 };
print "$r\n";
```

```behavior
parses: yes
```

```output
8
```

```tokens
one word whose text is "do"
```

```ir
main::__PROGRAM__: {start: 0, returns: [12], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EnvRead, {key: X}, ~, ~, Str], # 2
  [Constant, {const_type: integer, value: "7"}, ~, ~, Int], # 3
  [DefinedOr, ~, [2, 3], ~, Str], # 4
  [Coerce, {from_repr: Str, to_repr: Num}, [4], ~, Num], # 5
  [Constant, {const_type: integer, value: "1"}, ~, ~, Int], # 6
  [Add, ~, [5, 6], ~, Num], # 7
  [Coerce, {from_repr: Unknown, to_repr: Str}, [7], ~, Str], # 8
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 9
  [Concat, ~, [8, 9], ~, Str], # 10
  [Print, ~, [10], 0, Scalar], # 11
  [Return, ~, [1], 11]]} # 12
```

## `eval BLOCK` is a control construct

It emits `entertry`/`leavetry` and never `entereval`. Measured, the two
constructs wearing the `eval` keyword share no op at all: `eval { 1 }`
emits `entertry`/`leavetry`, `eval "1"` emits `entereval`. The STRING form
compiles Perl the compiler never saw -- it hands a region back to the lexer
with no delimiter at all -- and lives in `14_recursive`, which already
claims `entereval`.

This form does none of that. The block is ordinary Perl, compiled once, at
the ordinary time. What `entertry` adds is a FRAME: a marked point the
runtime can unwind back to when something inside the block fails. That is
a control transfer in the same family as this tier's `next`, `last` and
`goto` -- a jump whose target is named by the construct rather than by a
label, and whose distinction is that nothing in the source SPELLS the jump.

THE OPERAND IS DIVISION BY ZERO, NOT `die`, and that is a budget fact
rather than a stylistic one. When this case was written `die` was claimed
by no tier at or before 06, so `eval { die "x" }` reached forward and the
lint refused it. Division by zero is a runtime failure this tier could
already spell -- `divide` is tier 04's -- and it exercises the same frame.
The case is left as measured now that `die` is claimed: it is still the
one that shows `entertry` catching a failure the source does not raise by
name.

Note the ADDRESSES in the measured stream: `entertry` at 8 jumps to j, the
block body runs at j-m, and `leavetry` is numbered 9 -- the frame ops
bracket the block in source order while sitting outside it in execution
order. That is the shape a parser gets wrong when it treats `eval` as a
named unary over a hash constructor.

THE BEHAVIOURAL PIN IS THE DISCRIMINATING HALF, and it is exit status as
much as output. Measured, the same statement without the block does not
print anything: `my $r = 10 / $d // "trapped"` exits 255 with
`Illegal division by zero at -e line 1.` A parser that dropped the block,
or evaluated its contents outside the frame, produces a program that
aborts where this one completes.

```perl
my $d = $ENV{X} // 0;
my $r = eval { 10 / $d } // "trapped";
print "$r\n";
```

```behavior
parses: yes
```

```output
trapped
```

```tokens
one word whose text is "eval"
```

```ir
main::__PROGRAM__: {start: 0, returns: [17], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "10"}, ~, ~, Int], # 2
  [Coerce, {from_repr: Int, to_repr: Num}, [2], ~, Num], # 3
  [EnvRead, {key: X}, ~, ~, Str], # 4
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 5
  [DefinedOr, ~, [4, 5], ~, Str], # 6
  [Coerce, {from_repr: Str, to_repr: Num}, [6], ~, Num], # 7
  [Divide, ~, [3, 7], ~, Num], # 8
  [Region, {eval_entry: 0}, [0]], # 9
  [Phi, {region: 9}, [8, 1], ~, Scalar], # 10
  [Constant, {const_type: string, value: trapped}, ~, ~, Str], # 11
  [DefinedOr, ~, [10, 11], ~, Scalar], # 12
  [Coerce, {from_repr: Unknown, to_repr: Str}, [12], ~, Str], # 13
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 14
  [Concat, ~, [13, 14], ~, Str], # 15
  [Print, ~, [15], 9, Scalar], # 16
  [Return, ~, [1], 16]]} # 17
```

## `die` is a list operator, and its extent is a parse question

Where the argument list ends is a question the optree cannot answer and
`$@` can. Measured, `die $g, "b\n"` takes BOTH arguments -- `pushmark`,
two operands, `die` -- while `die($g), "b\n"` takes one, and the `"b\n"`
does not appear in the optree AT ALL: it is a constant in void context and
the optimiser deletes it.

So the two parses differ by an op present in one and absent in the other,
which reads like a difference an op check could see -- but a parser
binding too LITTLE produces exactly the narrow stream, and nothing in it
says which parse it came from. `$@` says: the wide parse concatenates both
arguments into the message, the narrow one carries `$g` alone.

BOTH MESSAGES END IN A NEWLINE ON PURPOSE. `die` appends
` at FILE line N.` to a message that does not, and FILE is the path the
harness wrote its temp copy to -- a different string on every run and on
every machine. A trailing newline suppresses the suffix, which is what
makes this output reproducible rather than merely correct once.

The token fact falsifies two lexers at once: no BARE word `wide` exists,
because the name appears only as the variable `$wide` and inside the
string `"wide="`. A lexer that split the sigil from its name, or that
lexed inside a string literal, emits one.

```perl
my $g = $ENV{X} // "a\n";
eval { die $g, "b\n" };
my $wide = $@;
eval { die($g), "b\n" };
print "wide=", $wide, "narrow=", $@;
```

```behavior
parses: yes
```

```output
wide=a
b
narrow=a
```

```tokens
no word whose text is "wide"
```

```ir
main::__PROGRAM__: {start: 0, returns: [18], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "wide="}, ~, ~, Str], # 2
  [MemStart], # 3
  [EnvRead, {key: X}, ~, ~, Str], # 4
  [Constant, {const_type: string, value: "a\n"}, ~, ~, Str], # 5
  [DefinedOr, ~, [4, 5], ~, Str], # 6
  [Constant, {const_type: string, value: "b\n"}, ~, ~, Str], # 7
  [Unwind, ~, [6, 7], 0], # 8
  [Region, {eval_entry: 0}, [8]], # 9
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [3], 9, Scalar], # 10
  [Coerce, {from_repr: Unknown, to_repr: Str}, [10], ~, Str], # 11
  [Constant, {const_type: string, value: "narrow="}, ~, ~, Str], # 12
  [Unwind, ~, [6], 10], # 13
  [Region, {eval_entry: 10}, [13]], # 14
  [EntryDef, {package: main, sigil: $, symbol: "@"}, [3], 14, Scalar], # 15
  [Coerce, {from_repr: Unknown, to_repr: Str}, [15], ~, Str], # 16
  [Print, ~, [2, 11, 12, 16], 15, Scalar], # 17
  [Return, ~, [1], 17]]} # 18
```

## `exit` leaves the program, and `eval BLOCK` does not catch it

`exit` is the same shape as `die` -- a named unary in statement position
that the following statement never reaches -- and the difference is the
only thing worth measuring. Measured, the `entertry` frame is BUILT,
bracketing the block exactly as it does in the `eval BLOCK` case, and the
`exit` goes straight through it. Swap `exit $c` for `die $c` and the same
frame catches, the program continues, and `trapped` prints. Same syntax,
same ops around it, opposite outcome, and only running it shows which.

THE DISCRIMINATING PIN IS AN ABSENCE, and the optree is what makes it a
claim rather than an accident. `print "trapped\n"` COMPILES -- its ops are
in the binary, at addresses after the `exit` -- and never runs. So this
case asserts two things at once that a single spelling cannot fake: the
statement is real perl the compiler accepted, and control never arrives at
it. A parser that treated `exit` as an ordinary bareword call would
compile the same ops and print `trapped` as well; a parser that dropped
the trailing statement as unreachable would print the same one line while
failing `parses` on a statement it never built.

THE RUNNER SEES THIS, which was checked rather than assumed. `askPerl` in
`internal/conformance/run.go` execs the file and reads `.Output()`, which
returns stdout whether or not the process exits non-zero -- and `exit 0`
is not an error at all, so nothing about the early termination is hidden
from the comparison.

The status comes from `$ENV{X}` not only for this tier's constant-erasure
reason: an `exit` whose status is a literal would still terminate, but the
value would be one the optimiser folded rather than one the program
computed, and `exit` takes an EXPRESSION.

```perl
my $c = $ENV{X} // 0;
print "ran\n";
eval { exit $c };
print "trapped\n";
```

```behavior
parses: yes
```

```output
ran
```

```tokens
one word whose text is "exit"
```

```ir
main::__PROGRAM__: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: string, value: "trapped\n"}, ~, ~, Str], # 2
  [EnvRead, {key: X}, ~, ~, Str], # 3
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 4
  [DefinedOr, ~, [3, 4], ~, Str], # 5
  [Constant, {const_type: string, value: "ran\n"}, ~, ~, Str], # 6
  [Print, ~, [6], 0, Scalar], # 7
  [Call, {dispatch_kind: builtin, name: exit, param_names: []}, [5], 7, Unknown], # 8
  [Region, {eval_entry: 7}, [8]], # 9
  [Print, ~, [2], 9, Scalar], # 10
  [Return, ~, [1], 10]]} # 11
```

## `time` is niladic

It parses with no argument at all, and it is the one construct in the
corpus whose value cannot be asserted. It is in a control tier because 06
is the earliest tier that can hold it and no earlier tier can: a
non-deterministic builtin is observable only through a COMPARISON, the
comparison needs `gt` from `04_operators`, and the ternary that renders
the result needs this tier's `cond_expr`. The lint is
`ops(file) subset-of union ops(tiers <= N)`, so the first tier that can
hold both is 06. Measured, the case emits `cond_expr const enter gt leave
nextstate padsv padsv_store print pushmark time`.

Tier 03 was the first placement proposed, on the ground that it already
claims `localtime` and the two share a clock. Measured, that does not
survive: tier 03's subject is the DISCRIMINATING PAIR, and `time` has
none. `my $n = () = time; my $s = time; my @c = ($s);` printing
`"$n ", scalar(@c)` gives `1 1`, where `localtime`
gives `9 1`. Same clock, different subject.

WHAT IS DISTINCTIVE IS THE ARITY. `time` takes no argument and no
parentheses, and unlike every other named operator in the corpus there is
no form of it that takes one. Measured, `my $t = time 1;` is a syntax
error: `Number found where operator expected (Do you need to predeclare
"time"?)`. So a parser that treats named operators uniformly -- callee,
then a greedy argument extent -- gets this one wrong in the direction of
accepting too much. The source puts `time` immediately before a `;` with
nothing between, which is the whole of its grammar.

THE COMPARISON IS WHAT MAKES IT OBSERVABLE, and it is not a workaround.
`time` returns seconds since the epoch, so pinning its value would make
the case fail one second later. Pinning a PROPERTY of the value is the
only assertion available: 1000000000 is 2001-09-09, so any clock later
than that gives `past`. `impossible` is the other branch's text on purpose
-- it names what a failure would mean rather than describing the branch.

NO CONSTANT ANYWHERE NEAR THE CALL. `$t` is a runtime value the optimiser
cannot see through, so the `gt` and the `cond_expr` are both in the
binary. That is why the value is bound first and compared second rather
than written as `time > 1000000000` in one expression.

The token fact is the niladic claim in the only form the grammar has, and
it cannot be satisfied by a substring: `checkTokenFact`
(`internal/conformance/fact.go:50`) compares `tokenText == text` on the
token's FULL text, never as a substring, which is what protects `time`
from `localtime`.

```perl
my $t = time;
print $t > 1000000000 ? "past" : "impossible", "\n";
```

```behavior
parses: yes
```

```output
past
```

```tokens
one word whose text is "time"
```

```ir
main::__PROGRAM__: {start: 0, returns: [10], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Call, {dispatch_kind: builtin, name: time, param_names: []}, ~, ~, Unknown], # 2
  [Constant, {const_type: integer, value: "1000000000"}, ~, ~, Int], # 3
  [NumGt, ~, [2, 3], ~, Boolean], # 4
  [Constant, {const_type: string, value: past}, ~, ~, Str], # 5
  [Constant, {const_type: string, value: impossible}, ~, ~, Str], # 6
  [TernaryExpr, ~, [4, 5, 6], ~, Str], # 7
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 8
  [Print, ~, [7, 8], 0, Scalar], # 9
  [Return, ~, [1], 9]]} # 10
```
