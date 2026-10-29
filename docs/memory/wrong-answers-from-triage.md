# Three wrong answers the census missed, found by triaging its refusals (356 -> ?)

A read-only triage of the 66 remaining refusals ran probes next to each
case and found three shapes the census does not cover where chalk or the
producer gave a **wrong answer**. All three were pre-existing at pin
5c60242f. All three are now refusals, each with a test that failed first.

## W1 (chalk): an array, hash or list argument bound as one argument

`sub f { my ($c, $a) = @_; $a + 1 } f(@x)` gave 1 for perl's 3. The same
went for `f(g())` with g returning a list, and `f(%h)` read by `$_[N]`.

The "flattens into @_" guard ran only when the callee read `@_` as a whole
list (`$args_array`). It missed every positional path: shift,
`my (...) = @_`, `$_[N]`, signatures and the slurpy binding. It now runs
for every argument-passing inline. It refuses an argument stamped Array,
Hash or List, or an Unknown-stamped Call with `want => 'list'`. It does not
use the old whitelist, which would refuse Unknown scalars that lower
correctly today.

## W2 (producer): `&&`/`||` in list context keeping one value of a list

`my @r = @a && (3, 4, 5)` reached the wire as `And(Count(@a), 5)`: one
element for perl's three. The list's pushmark is nulled, so all three
consts land on the arm's stack. The value-context logop builder popped only
the top one. It now refuses (`GAP: a short-circuit whose right side is a
list of several values`) when the right side leaves more than one value.
Lowering a list-context `&&` properly is still to do; case 089 needs it.

## W3 (producer): a method's class copied from any invocant call

`$x->b->n` was emitted with class_name K, the class of `$x`, though `->b`
returns a Box. lli rejected that module, but a program whose types lined up
would have called the wrong method. The class now propagates only from a
constructor invocant (`->new`). A method on another method's value has no
class_name and goes through run-time dispatch or a refusal.

## Triage (for picking the next causes)

Groups by cases unblocked per effort, from the triage agent:
- **Producer, size S:**
  - 153: a `%`/`@` field default typed from its graph (List) instead of
    its sigil.
  - 163: an anon sub's signature not on the wire.
- **Both, size M:** a Return in its caller's context (075, 129, 246, 144,
  091), i.e. the two faces for every context-sensitive `return EXPR`.
- **Both:**
  - `while (my $x = shift @a)` (151, 195): the Loop forks control to the
    shift and the test.
  - a loop phi with a Str start and arithmetic back edge (326).
- **Large, or refused for now:**
  - qx, glob, readpipe and format (014, 365, 366, 370);
  - computed goto (308) and Unicode (229);
  - regex code blocks (286–288), `\G` with a runtime pattern (385) and
    `s///ge` (111);
  - recursion (248), closures writing what they captured (134, 135);
  - `each` (021, 002), whose hash order is perl's random order.

Also: `tools/chalk-lower.pl` dies "Wide character in say" on a GAP message
containing an em dash. The case still counts as refused, but its reason is
lost.

## Lessons

- **Probe beyond the cases.** The census measures 430 programs, and a
  refusal's neighbours can be wrong answers. Each fixed cause should be
  probed with the shapes next to it: an array where a scalar was, list
  context where scalar was, a method on a method's value.
- **Process slip.** The producer was edited and installed while a
  `SON_RATCHET=1` ratchet run was reading it. That run was stopped and must
  be redone on a quiet tree.
