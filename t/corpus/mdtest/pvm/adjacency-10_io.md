# Every construct, each beside another

One body holding every construct this tier introduces, each adjacent to
another.

**Tier 10 io.** Introduces nothing of its own; the mixture is the
subject. Depends on 03_context.

The tier's other cases are one construct each, which is what makes them
diagnosable. That same property is why such a corpus cannot reach an
ADJACENCY bug: a parser handling every construct alone and mishandling
a pair goes green over the pair.

## The whole tier in one body

The pairs that matter are the ones a one-construct case cannot make.

A scalar readline followed by a LIST readline on the SAME handle is the
whole of this tier's context dependency in two adjacent statements --
the second reads what the first left, so the printed `2` is only
correct if both contexts were resolved and resolved DIFFERENTLY. The
two readline cases each open a fresh handle and so can never disagree
about position.

The second pairing is `eof` inside a print LIST that also holds an
array, which puts the tier's own op in an argument position rather than
alone in a statement.

THE THIRD PAIRING IS `select` WITH `say`, and it is the one that needs
two constructs most. `say "round trip"` names NO HANDLE, and its bytes
land in `$buf` rather than on stdout, because the `select($out)` above
it changed where "no handle" points. Neither case alone can make that
claim: the `say` case passes its handle explicitly and the `select`
case redirects a `print`. Here the two constructs are the same
assertion -- a parser that dropped either one puts `round trip` on
stdout and leaves the buffer empty.

The four-argument `select` follows, the other operator sharing that
name: measured, `select($out)` emits `select` and
`select(undef,undef,undef,0)` emits `sselect`, a different op reached
by a different argument count. Both spellings are here because the
tier's declared set holds both and an adjacency case must reach every
op the tier introduces.

The pairing with 03_context is the scalar-versus-list readline itself:
context is not a separate construct to place beside this one, it is the
thing selecting which readline happens.

The ops this reaches beyond the tier's own, all claimed earlier and
none new: `gv`, `padav` and `aassign` (02), `cond_expr` and `goto` from
the ternary (06), `undef` from the syscall arguments (04), `srefgen`
from `\my $buf` (08).

`use feature "say"` is required and is not decoration: without it `say`
is not this tier's op at all but a method call. Measured, the pragma
changes no op in this body beyond enabling `say` itself.

```perl
use feature "say";
open(my $in, "<", \"first\nsecond\nthird\n");
my $head = <$in>;
my @rest = <$in>;
print STDOUT $head;
print STDOUT scalar(@rest), " left, eof ", (eof($in) ? "yes" : "no"), "\n";
close($in);
open(my $out, ">", \my $buf);
my $prev = select($out);
say "round trip";
select($prev);
close($out);
my $ready = select(undef, undef, undef, 0);
our $AUTOLOAD;
sub AUTOLOAD { my $n = $AUTOLOAD; $n =~ s/.*:://; return "auto:$n" }
*sq = sub { $_[0] * $_[0] };
print $buf, "ready $ready sq ", sq(3), " glob ", ref(\*STDOUT), " ", missing(), "\n";
```

```behavior
parses: yes
```

```output
first
2 left, eof yes
round trip
ready 0 sq 9 glob GLOB auto:missing
```

```ir
main::AUTOLOAD: {start: 0, returns: [11], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: "auto:"}, ~, ~, Str], # 1
  [MemStart], # 2
  [PadAccess, {sigil: $, symbol: "n"}, [2], ~, Unknown], # 3
  [EntryDef, {package: main, sigil: $, symbol: AUTOLOAD}, [2], ~, Scalar], # 4
  [Assign, ~, [3, 4], 0, Scalar], # 5
  [PadAccess, {sigil: $, symbol: "n"}, [5], ~, Unknown], # 6
  [RegexSubst, {flags: "", pattern: ".*::", replacement: ""}, [6, 5], 5, Str], # 7
  [PadAccess, {sigil: $, symbol: "n"}, [7], ~, Str], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Concat, ~, [1, 9], ~, Str], # 10
  [Return, ~, [10], 7]]} # 11
main::__PROGRAM__: {start: 0, returns: [55], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [EntryDef, {package: main, sigil: "&", symbol: sq}, ~, ~, Unknown], # 2
  [AnonSub, {name: main::__PROGRAM__::__ANON__:16:25}, ~, ~, CodeRef], # 3
  [MemStart], # 4
  [PadAccess, {sigil: $, symbol: out}, ~, ~, GlobRef], # 5
  [Constant, {const_type: string, value: ">"}, ~, ~, Str], # 6
  [PadAccess, {sigil: $, symbol: buf}, [4], ~, Unknown], # 7
  [Ref, ~, [7], ~, Unknown], # 8
  [PadAccess, {sigil: $, symbol: in}, ~, ~, GlobRef], # 9
  [Constant, {const_type: glob, value: STDOUT}, ~, ~, Glob], # 10
  [Constant, {const_type: string, value: "<"}, ~, ~, Str], # 11
  [Constant, {const_type: ref, value: "first\nsecond\nthird\n"}, ~, ~, ScalarRef], # 12
  [Call, {dispatch_kind: builtin, name: open, param_names: []}, [9, 11, 12], 0, Scalar], # 13
  [Call, {dispatch_kind: builtin, name: readline, param_names: []}, [9], 13, Scalar], # 14
  [Call, {dispatch_kind: builtin, name: readline, param_names: []}, [9], 14, List], # 15
  [ArrayLiteral, {sigil: "@", symbol: rest}, [15], ~, Array], # 16
  [Count, ~, [16, 4], ~, Int], # 17
  [Coerce, {from_repr: Int, to_repr: Str}, [17], ~, Str], # 18
  [Constant, {const_type: string, value: " left, eof "}, ~, ~, Str], # 19
  [Coerce, {from_repr: Scalar, to_repr: Str}, [14], ~, Str], # 20
  [Print, {has_filehandle: true}, [10, 20], 15, Scalar], # 21
  [Call, {dispatch_kind: builtin, name: eof, param_names: []}, [9], 21, Unknown], # 22
  [Constant, {const_type: string, value: "yes"}, ~, ~, Str], # 23
  [Constant, {const_type: string, value: "no"}, ~, ~, Str], # 24
  [TernaryExpr, ~, [22, 23, 24], ~, Str], # 25
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 26
  [Print, {has_filehandle: true}, [10, 18, 19, 25, 26], 22, Scalar], # 27
  [Call, {dispatch_kind: builtin, name: close, param_names: []}, [9], 27, Boolean], # 28
  [Call, {dispatch_kind: builtin, name: open, param_names: []}, [5, 6, 8], 28, Scalar], # 29
  [Call, {dispatch_kind: builtin, name: select, param_names: []}, [5], 29, Unknown], # 30
  [Constant, {const_type: string, value: "round trip"}, ~, ~, Str], # 31
  [Print, ~, [31, 26], 30, Scalar], # 32
  [Call, {dispatch_kind: builtin, name: select, param_names: []}, [30], 32, Unknown], # 33
  [Call, {dispatch_kind: builtin, name: close, param_names: []}, [5], 33, Boolean], # 34
  [EntryWrite, {binds: true}, [2, 3, 4], 34, Unknown], # 35
  [PadAccess, {sigil: $, symbol: buf}, [35], ~, Str], # 36
  [Coerce, {from_repr: Unknown, to_repr: Str}, [36], ~, Str], # 37
  [Constant, {const_type: string, value: "ready "}, ~, ~, Str], # 38
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 39
  [Call, {dispatch_kind: builtin, name: sselect, param_names: []}, [1, 1, 1, 39], ~, Unknown], # 40
  [Coerce, {from_repr: Unknown, to_repr: Str}, [40], ~, Str], # 41
  [Concat, ~, [38, 41], ~, Str], # 42
  [Constant, {const_type: string, value: " sq "}, ~, ~, Str], # 43
  [Concat, ~, [42, 43], ~, Str], # 44
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 45
  [Call, {dispatch_kind: direct, name: main::sq, param_names: [], want: list}, [45], 35, Unknown], # 46
  [Coerce, {from_repr: Unknown, to_repr: Str}, [46], ~, Str], # 47
  [Constant, {const_type: string, value: " glob "}, ~, ~, Str], # 48
  [Ref, ~, [10], ~, GlobRef], # 49
  [RefType, ~, [49], ~, Str], # 50
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 51
  [Call, {dispatch_kind: direct, name: main::missing, param_names: [], want: list}, ~, 46, Unknown], # 52
  [Coerce, {from_repr: Unknown, to_repr: Str}, [52], ~, Str], # 53
  [Print, ~, [37, 44, 47, 48, 50, 51, 53, 26], 52, Scalar], # 54
  [Return, ~, [1], 54], # 55
  [EntryDef, {package: main, sigil: $, symbol: AUTOLOAD}, [4], ~, Scalar]]} # 56
main::__PROGRAM__::__ANON__:16:25: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, ~, [1, 2, 3], ~, Scalar], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Multiply, ~, [5, 5], ~, Num], # 6
  [Return, ~, [6], 0]]} # 7
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: say}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3, 4], 0, Unknown], # 5
  [Call, {class_name: feature, dispatch_kind: method, name: import, param_names: []}, [1, 2], 5, Unknown], # 6
  [Return, ~, [6], 6]]} # 7
```
