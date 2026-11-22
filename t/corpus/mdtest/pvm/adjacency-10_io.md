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
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown, 2], # 3
  [EntryDef, {package: main, sigil: $, symbol: AUTOLOAD}, ~, ~, Scalar, 2], # 4
  [Assign, ~, [3, 4], 0, Scalar, 2, true], # 5
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Unknown, 5], # 6
  [RegexSubst, {flags: "", pattern: ".*::", replacement: ""}, [6], 5, Str, 5, true], # 7
  [PadAccess, {sigil: $, symbol: "n"}, ~, ~, Str, 7], # 8
  [Coerce, {from_repr: Unknown, to_repr: Str}, [8], ~, Str], # 9
  [Concat, ~, [1, 9], ~, Str], # 10
  [Return, ~, [10], 7, ~, 7]]} # 11
main::__PROGRAM__: {start: 0, returns: [55], nodes: [
  [Start], # 0
  [Constant, {const_type: undef, value: ~}, ~, ~, Undef], # 1
  [Constant, {const_type: integer, value: "3"}, ~, ~, Int], # 2
  [EntryDef, {package: main, sigil: "&", symbol: sq}, ~, ~, Unknown], # 3
  [AnonSub, {name: main::__PROGRAM__::__ANON__:16:25}, ~, ~, CodeRef], # 4
  [PadAccess, {sigil: $, symbol: out}, ~, ~, GlobRef], # 5
  [Constant, {const_type: string, value: ">"}, ~, ~, Str], # 6
  [PadAccess, {sigil: $, symbol: in}, ~, ~, GlobRef], # 7
  [Constant, {const_type: glob, value: STDOUT}, ~, ~, Glob], # 8
  [Constant, {const_type: string, value: "<"}, ~, ~, Str], # 9
  [Constant, {const_type: ref, value: "first\nsecond\nthird\n"}, ~, ~, ScalarRef], # 10
  [MemStart], # 11
  [Call, {dispatch_kind: builtin, name: open, param_names: []}, [7, 9, 10], 0, "Maybe[Int]", 11, true], # 12
  [Call, {dispatch_kind: builtin, name: readline, param_names: []}, [7], 12, Scalar, 12, true], # 13
  [Call, {dispatch_kind: builtin, name: readline, param_names: []}, [7], 13, List, 13, true], # 14
  [ArrayLiteral, {sigil: "@", symbol: rest}, [14], ~, Array], # 15
  [Count, ~, [15], ~, Int, 14], # 16
  [Coerce, {from_repr: Int, to_repr: Str}, [16], ~, Str], # 17
  [Constant, {const_type: string, value: " left, eof "}, ~, ~, Str], # 18
  [Coerce, {from_repr: Scalar, to_repr: Str}, [13], ~, Str], # 19
  [Print, {has_filehandle: true}, [8, 19], 14, "Maybe[Boolean]"], # 20
  [Call, {dispatch_kind: builtin, name: eof, param_names: []}, [7], 20, Boolean, 14, true], # 21
  [Constant, {const_type: string, value: "yes"}, ~, ~, Str], # 22
  [Constant, {const_type: string, value: "no"}, ~, ~, Str], # 23
  [TernaryExpr, ~, [21, 22, 23], ~, Str], # 24
  [Constant, {const_type: string, value: "\n"}, ~, ~, Str], # 25
  [Print, {has_filehandle: true}, [8, 17, 18, 24, 25], 21, "Maybe[Boolean]"], # 26
  [Call, {dispatch_kind: builtin, name: close, param_names: []}, [7], 26, Boolean, 21, true], # 27
  [PadAccess, {sigil: $, symbol: buf}, ~, ~, Unknown, 27], # 28
  [Ref, ~, [28], ~, Unknown], # 29
  [Call, {dispatch_kind: builtin, name: open, param_names: []}, [5, 6, 29], 27, "Maybe[Int]", 27, true], # 30
  [Call, {dispatch_kind: builtin, name: select, param_names: []}, [5], 30, Unknown, 30], # 31
  [Constant, {const_type: string, value: "round trip"}, ~, ~, Str], # 32
  [Print, ~, [32, 25], 31, "Maybe[Boolean]"], # 33
  [Call, {dispatch_kind: builtin, name: select, param_names: []}, [31], 33, Unknown, 30], # 34
  [Call, {dispatch_kind: builtin, name: close, param_names: []}, [5], 34, Boolean, 30, true], # 35
  [EntryWrite, {binds: true}, [3, 4], 35, Unknown, 35, true], # 36
  [Call, {dispatch_kind: direct, file: "/tmp/ucZOh245UI/case.pl", line: 17, name: main::sq, package: main, param_names: [], want: list}, [2], 36, Unknown, 36, true], # 37
  [Call, {dispatch_kind: direct, file: "/tmp/ucZOh245UI/case.pl", line: 17, name: main::missing, package: main, param_names: [], want: list}, ~, 37, Unknown, 37, true], # 38
  [PadAccess, {sigil: $, symbol: buf}, ~, ~, Str, 38], # 39
  [Coerce, {from_repr: Unknown, to_repr: Str}, [39], ~, Str], # 40
  [Constant, {const_type: string, value: "ready "}, ~, ~, Str], # 41
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 42
  [Call, {dispatch_kind: builtin, name: sselect, param_names: []}, [1, 1, 1, 42], ~, Unknown], # 43
  [Coerce, {from_repr: Unknown, to_repr: Str}, [43], ~, Str], # 44
  [Concat, ~, [41, 44], ~, Str], # 45
  [Constant, {const_type: string, value: " sq "}, ~, ~, Str], # 46
  [Concat, ~, [45, 46], ~, Str], # 47
  [Coerce, {from_repr: Unknown, to_repr: Str}, [37], ~, Str], # 48
  [Constant, {const_type: string, value: " glob "}, ~, ~, Str], # 49
  [Ref, ~, [8], ~, GlobRef], # 50
  [RefType, ~, [50], ~, Str, 37], # 51
  [Constant, {const_type: string, value: " "}, ~, ~, Str], # 52
  [Coerce, {from_repr: Unknown, to_repr: Str}, [38], ~, Str], # 53
  [Print, ~, [40, 47, 48, 49, 51, 52, 53, 25], 38, "Maybe[Boolean]"], # 54
  [Return, {implicit: true}, [1], 54, ~, 38], # 55
  [PadAccess, {sigil: $, symbol: buf}, ~, ~, Unknown, 36], # 56
  [EntryDef, {package: main, sigil: $, symbol: AUTOLOAD}, ~, ~, Scalar, 35]]} # 57
main::__PROGRAM__::__ANON__:16:25: {start: 0, returns: [7], nodes: [
  [Start], # 0
  [ArgsSource, ~, ~, ~, Array], # 1
  [Constant, {const_type: integer, value: "0"}, ~, ~, Int], # 2
  [MemStart], # 3
  [Subscript, {kind: array}, [1, 2], ~, Scalar, 3], # 4
  [Coerce, {from_repr: Scalar, to_repr: Num}, [4], ~, Num], # 5
  [Multiply, ~, [5, 5], ~, Num], # 6
  [Return, {implicit: true}, [6], 0, ~, 3]]} # 7
"BEGIN 1": {start: 0, returns: [7], nodes: [
  [Start], # 0
  [Constant, {const_type: string, value: feature}, ~, ~, Str], # 1
  [Constant, {const_type: string, value: say}, ~, ~, Str], # 2
  [Constant, {const_type: string, value: feature.pm}, ~, ~, Str], # 3
  [MemStart], # 4
  [Call, {dispatch_kind: builtin, name: require, param_names: []}, [3], 0, Unknown, 4, true], # 5
  [Call, {class_name: feature, dispatch_kind: method, file: "/tmp/ucZOh245UI/case.pl", line: 1, name: import, package: main, param_names: []}, [1, 2], 5, Unknown, 5, true], # 6
  [Return, {implicit: true}, [6], 6, ~, 6]]} # 7
```
