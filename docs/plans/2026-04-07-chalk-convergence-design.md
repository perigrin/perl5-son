# Chalk Convergence: Full Node Parity for perl5-son

**Date:** 2026-04-07
**Goal:** Make perl5-son represent every IR node type Chalk produces, with matching class hierarchy, content_hash protocol, and type lattice.

## Motivation

Chalk and perl5-son both implement Sea of Nodes IR for Perl. To compare their outputs with `SoN::Compare`, both must share the same node vocabulary. Chalk has 76 node types; perl5-son has 49. This design closes the gap.

## 1. Class Hierarchy

Add three abstract base classes to mirror Chalk's inheritance:

- **`SoN::IR::Node::BinOp`** — fields: `$left`, `$right`; abstract method: `op_str()`
- **`SoN::IR::Node::UnaryOp`** — field: `$operand`; abstract method: `op_str()`
- **`SoN::IR::Node::Aggregate`** — variable-length inputs (elements)

Reparent existing nodes:

| Base Class | Existing Nodes to Reparent |
|-----------|---------------------------|
| BinOp | Add, Subtract, Multiply, Divide, Modulo, Power, Concat, NumEq, NumNe, NumLt, NumGt, NumLe, NumGe, NumCmp, StrEq, StrNe, StrLt, StrGt, StrLe, StrGe, StrCmp, And, Or, BitAnd, BitOr, BitXor, LeftShift, RightShift, Assign |
| UnaryOp | Not, Negate, Complement, Defined |

Backwards-compatible: BinOp/UnaryOp inherit from Node, so `isa SoN::IR::Node` still holds.

## 2. New Node Types (21 classes)

### BinOp (8)

| Node | op_str | Perl Syntax |
|------|--------|-------------|
| Repeat | `x` | `"ab" x 3` |
| Match | `=~` | `$s =~ /pat/` |
| NotMatch | `!~` | `$s !~ /pat/` |
| DefinedOr | `//` | `$x // $default` |
| Xor | `xor` | `$a xor $b` |
| Range | `..` | `1..10` |
| Yada | `...` | `...` (unimplemented) |
| IsaOp | `isa` | `$obj isa Class` |

Also: **CompoundAssign** (BinOp + `$op` field for `+=`, `-=`, etc.)

### UnaryOp (2)

| Node | op_str | Perl Syntax |
|------|--------|-------------|
| UnaryPlus | `+` | `+$x` (numeric coercion) |
| Ref | `\` | `\@array` |

Also: **PostfixDeref** (UnaryOp + `$sigil` field for `->@*`, `->%*`, etc.)

### Aggregate (3)

| Node | Purpose |
|------|---------|
| HashRef | Anonymous hash constructor `{ k => v }` |
| ArrayRef | Anonymous array constructor `[1, 2, 3]` |
| Interpolate | String interpolation segments |

### CFG (1)

| Node | Purpose |
|------|---------|
| Unwind | Exception flow (die/croak). Replaces Call for die. Unique ID, not hash-consed. |

### Standalone (6)

| Node | Purpose |
|------|---------|
| TernaryExpr | `? :` before lowering to If/Proj/Region/Phi |
| StructRef | Optimizer: promoted hash-to-struct |
| StructFieldAccess | Optimizer: field read on promoted struct |
| AnonSub | Anonymous sub/closure |
| RegexMatch | `m//` as first-class node |
| RegexSubst | `s///` as first-class node |
| TryCatch | try/catch block |
| VarDecl | `my`/`our`/`state` declaration wrapper |
| BacktickExpr | Backtick/qx commands |

## 3. FromOptree Wiring

Opcode-to-node mapping in `OpMap.pm`:

| Opcode(s) | Node |
|-----------|------|
| `repeat` | Repeat |
| `match`, `smartmatch` | Match |
| not-match context | NotMatch |
| `dorassign`, defined-or | DefinedOr |
| `xor` | Xor |
| `range`, `flop` | Range |
| `stub` (yada) | Yada |
| `isa` | IsaOp |
| `i_add` etc. + OPf_STACKED | CompoundAssign |
| unary `+` on `negate` | UnaryPlus |
| `srefgen`, `refgen` | Ref |
| `rv2av`/`rv2hv` postfix | PostfixDeref |
| `anonhash` | HashRef |
| `anonlist` (arrayref) | ArrayRef |
| concat chains + constants | Interpolate |
| `die` | Unwind |
| `cond_expr` | TernaryExpr |
| `anoncode` | AnonSub |
| `match` (regex) | RegexMatch |
| `subst` | RegexSubst |
| `entertrycatch` | TryCatch |
| pad ops + OPpLVAL_INTRO | VarDecl |
| `backtick` | BacktickExpr |

StructRef and StructFieldAccess are optimizer-produced — FromOptree does not emit them.

## 4. Stamp Lattice Expansion

Add four types to `SoN::IR::Stamp`:

```
            Unknown
          /   |    \
       Scalar Void  List
       /  |  \  \
     Str Undef Boolean DualVar Ref
      |                  |
     Num     ScalarRef ArrayRef HashRef CodeRef Object Regex Glob
      |
     Int
```

- **Void** — subs/statements returning nothing
- **List** — list-context returns (distinct from ArrayRef)
- **Regex** — `qr//` compiled regex (under Ref)
- **Glob** — typeglobs (under Ref)

The `_ancestors` and `_depth` methods extend to cover these. No algorithmic change to meet/join.

## 5. content_hash Protocol

### Nodes with custom content_hash

| Node | Format |
|------|--------|
| Constant | `Constant\|const_type=$type\|value=$value` (add `$const_type` field) |
| CompoundAssign | `CompoundAssign\|op=$op\|inputs...` |
| PostfixDeref | `PostfixDeref\|sigil=$sigil\|inputs...` |
| RegexMatch | `RegexMatch\|pattern=$pat\|flags=$flags\|inputs...` |
| RegexSubst | `RegexSubst\|pattern=$pat\|replacement=$repl\|flags=$flags\|inputs...` |
| VarDecl | `VarDecl\|scope=$scope\|inputs...` |
| AnonSub | `AnonSub\|inputs...` |
| BacktickExpr | `BacktickExpr\|inputs...` |

### Nodes using default content_hash (operation + inputs)

All plain BinOps, UnaryOps, Aggregates, TernaryExpr, StructRef, StructFieldAccess, TryCatch.

### Constant alignment

perl5-son's Constant gains a `$const_type` field to match Chalk. Existing tests update for the new hash format.

### CFG nodes

Unwind gets a unique ID (like If, Region, Loop). Not hash-consed.

## 6. Scope and Non-Goals

**In scope:** Node classes, base class hierarchy, FromOptree wiring, Stamp lattice, content_hash parity.

**Out of scope:** SoN::Compare updates (separate work), optimization passes (StructRef promotion), Chalk-side adapter changes.
