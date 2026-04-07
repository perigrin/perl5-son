# SoN JSON Serialization and B::SoN Backend

**Date:** 2026-04-07
**Goal:** Serialize SoN IR graphs to deterministic JSON. Provide a Perl compiler backend (`perl -MO=SoN,json`) to dump compiled code as JSON. Enable Chalk to produce and load the same format.

## Motivation

Chalk and perl5-son now share the same IR node vocabulary (70 node types, matching hierarchy and content_hash). To validate Chalk's IR against Perl's compiled optree, both need to serialize to a common format. JSON is human-readable, diffable with standard tools, and machine-parseable.

## Components

### 1. SoN::Serialize::JSON (perl5-son)

Serialize and deserialize `SoN::IR::Graph` objects to/from JSON.

**`to_json(\%named_graphs)`** — Takes a hashref of `{ name => SoN::IR::Graph }`, returns a JSON string.

**`from_json($json_string)`** — Returns `{ name => SoN::IR::Graph }`.

### 2. B::SoN (perl5-son)

Perl compiler backend invoked via `perl -MO=SoN file.pm`.

**Options:**
- `perl -MO=SoN file.pm` — text output (SoN::Render::Text)
- `perl -MO=SoN,json file.pm` — JSON output (SoN::Serialize::JSON)

**CV discovery:** Walk the main optree recursively. Every CV encountered (via `anoncode`, `entersub` targets, stash entries) is translated via `SoN::FromOptree->translate()` and labeled by its qualified name (`Package::method`) or `ANON_$addr`.

### 3. Chalk::IR::Serialize::JSON (Chalk)

Same JSON schema, Chalk side. Two directions:

**`to_json($program)`** — Walk Chalk::IR::Program, extract per-method graphs, serialize.

**`from_json($json_string, $factory)`** — Load JSON into Chalk::IR::Node trees. Enables using perl5-son output as ground truth fixtures.

**Invocation:** `chalk --emit-son-json lib/Foo.pm`

## JSON Schema

```json
{
  "version": 1,
  "source": "lib/Foo.pm",
  "methods": {
    "Foo::new": {
      "nodes": [
        { "id": 0, "op": "Start", "inputs": [], "cfg": true },
        { "id": 1, "op": "Constant", "inputs": [],
          "fields": { "const_type": "integer", "value": "42" } },
        { "id": 2, "op": "Return", "inputs": [0, 1], "cfg": true }
      ],
      "start": 0,
      "returns": [2]
    }
  }
}
```

### Schema rules

- **Deterministic order:** Nodes sorted by topological position (via `Graph::nodes()`).
- **Positional IDs:** Renumbered 0, 1, 2... during serialization. Stable across runs.
- **`op`:** Operation name string. Matches between Chalk and perl5-son.
- **`inputs`:** Array of positional node IDs.
- **`fields`:** Only present when node has extra data beyond operation + inputs. Maps field name to string value. Field set depends on node type:
  - Constant: `const_type`, `value`
  - Call: `dispatch_kind`, `name`
  - Phi: `region` (ID of Region node)
  - Proj: `index`
  - PadAccess: `targ`, `varname`
  - FieldAccess: `field_index`, `field_stash`
  - StashAccess: `stash_name`, `var_name`
  - CompoundAssign: `op`
  - PostfixDeref: `sigil`
  - RegexMatch: `pattern`, `flags`
  - RegexSubst: `pattern`, `replacement`, `flags`
  - VarDecl: `scope`
- **`cfg`:** Boolean, present and true for CFG nodes (Start, Return, Unwind, If, Proj, Region, Loop).
- **`stamp`:** Optional string. Type lattice name if stamp is set on the node.

### Comparison workflow

```bash
perl -MO=SoN,json lib/Foo.pm > foo.perl.json
chalk --emit-son-json lib/Foo.pm > foo.chalk.json
diff foo.perl.json foo.chalk.json      # or jd, json-diff, jq, etc.
```

Byte-identical JSON for matching methods means the IRs agree. Any standard JSON diff tool explains divergences.

### Round-trip validation

```bash
# perl5-son round-trip
perl -MO=SoN,json lib/Foo.pm | son-load --verify

# Chalk loads perl5-son output as ground truth
perl -MO=SoN,json lib/Foo.pm > foo.perl.json
chalk --load-son-json foo.perl.json --verify
```

## Scope

**In scope:**
- `SoN::Serialize::JSON` (to_json, from_json)
- `B::SoN` compiler backend (text + json options)
- `Chalk::IR::Serialize::JSON` (to_json, from_json)
- JSON schema definition
- Tests for serialization round-trip and backend output

**Out of scope:**
- Custom comparison tools (use existing JSON diff)
- Optimization passes
- Chalk `--emit-son-json` CLI integration (separate from serializer)
