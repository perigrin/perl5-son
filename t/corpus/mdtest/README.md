# B::SoN's copy of the corpora

Our own copies of two mdtest corpora, each case carrying the graph B::SoN
makes of it inline, so a consumer can take the corpus one stage at a time:
the perl, its graph, and what perl says it does.

| directory | copied from | graph block |
|-----------|-------------|-------------|
| `pvm/`    | pvm `conformance/mdtest` at `cdce17ba` (origin/pu, 2026-09-29) | ```` ```ir ```` |
| `chalk/`  | Chalk `t/corpus/mdtest` at `5948f648` (HEAD, 2026-09-29)        | ```` ```son ```` |

These are copies, not links: they change here when we change them, and the
round-trip census, its ratchet and the drift check all measure them.

## The graph block

Compact flow YAML any YAML parser reads, written by
`tools/corpus-fill-ir.pl` from the wire JSON (`SoN::Render::WireYAML`):

    main::sign: {start: 0, returns: [14], nodes: [
      [Start], # 0
      [NumLt, ~, [6, 7], ~, Boolean], # 8
      [Region, {head: 9}, [10, 11]], # 12
      [Return, ~, [13], 12]]} # 14

One entry per graph (each sub by name, then phase blocks as `BEGIN n`).
`nodes` is a list whose index is the node's id; each node is
`[op, fields, inputs, control_in, stamp]`, trailing `~`s dropped. Scalars
keep their wire type. A graph B::SoN refuses is listed under `refused:`.

## Each corpus's convention

- `pvm/`: FORMAT.md reserves ```` ```ir ```` for B::SoN's graph, and a case
  is a whole program, translated as written.
- `chalk/`: ```` ```ir ```` is Chalk's own hand-written spec (with its `L:`
  verdict) and is left alone; ours is ```` ```son ```` beside it. A case is
  a fragment, translated as Chalk's harness runs it through B::SoN: pragmas
  and `class` declarations at file scope, the rest the body of
  `sub corpus_case`, whose graph is `main::corpus_case`.

## Keeping them current

    perl tools/corpus-fill-ir.pl            # refill both after a producer change
    perl tools/corpus-fill-ir.pl --check    # list drift, write nothing
    SON_CORPUS_IR=1 prove -l t/corpus-ir-blocks.t

To take a newer upstream, copy its committed tree over the directory (for
example `git -C ~/dev/pvm archive <rev> conformance/mdtest | tar -x
--strip-components=2 -C t/corpus/mdtest/pvm`), refill, and update the table
above.
