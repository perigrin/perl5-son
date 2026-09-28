# `open our $T` models the handle as an assignment target

Status: **recorded, not fixed.** Measured 2026-09-26. The last defect standing
between perl's `t/base/rs.t` and a clean round trip, along
[[2026-09-26-a-package-scalar-is-not-loop-carried]].

STILL NOT FIXED, 2026-09-28, whatever 46df9e5's message says. It reports this
file's TODO as passing on prove's `TODO passed: 1`, which a todo-wrapped
subtest prints even when its inner assertion fails. `prove -lv` shows
"Failed test (with amnesty)" and `close($eff15)` still emitted.

## The shape

`open my $T` round-trips. `open our $T` does not, and the discriminator is
exactly that word:

    {
        if (open our $T, "./foo") {
            my $line = <$T>;
            print "# $line\n";
            close $T;
        }
        else { print "not " }
        print "ok 1\n";
    }

    perl   # 1234567890123456789012345678901234567890 / ok 1
    ours   # (empty)                                  / not not ok 1

## The emission

    my $stale4 = $main::T;
    if (open($stale4, "./foo")) {
        my $eff9 = readline($stale4);
        $main::T = $eff9;                      # <- the defect
        print join('', (("# " . $line) . "\n"));   # <- $line undeclared
        close($eff9);                          # <- closes the LINE
        ...

Four symptoms, one cause: the package slot `$T` is being treated as the
ASSIGNMENT TARGET of the `readline`, so

- the line is stored into `$T` (`$main::T = $eff9`),
- `close` is handed that value rather than the handle,
- the `my $line` binding is lost (its value went to `$T` instead), and
- the read of `$T` as the open argument is a pre-store read, which the
  stale-read pass then binds to `$stale4` -- correct given the graph, and a
  symptom rather than a cause.

The `my` form has no `EntryWrite` at all and comes out right, which is what
says the defect is in the PACKAGE lvalue path and not in `open`, `readline` or
`close`.

## Where to look

`open our $T` compiles its handle operand as a package scalar in lvalue
position (`OPf_MOD` on the gvsv under the open), and something downstream is
taking that lvalue EntryDef as the destination for the next value on the
stack. The same "an lvalue EntryDef is a NAME TOKEN, not a read" distinction
that the pre/post increment fix turned on
(`t/from-optree-package-post-increment-yields-the-old-value.t`) is likely the
frame: here the name token is being consumed as a store target by an op that
should only be reading it as a handle.

## Guard

`t/from-optree-open-our-handle-round-trips.t` does not exist yet. The reduction
above is the whole test, and it must include the `open my $T` control -- that
is what distinguishes this defect from a general filehandle problem.
