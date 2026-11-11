---
name: B::SoN follows use/require
description: how a module the program loads gets onto the wire, and how emitters and chalk treat it
type: project
---
B::SoN follows `use`/literal `require` (perigrin, 2026-10-31; roadmap milestone 1).

- **What is followed:** the %INC delta since B::SoN loaded (`_followed_modules`), minus
  lowercase pragmas and %BUILTIN_MODULE (File::Glob, Errno, Tie::Hash::NamedCapture:
  perl loads these to implement glob, %!, %+; the program never named them).
- **Two predicates:** `_cv_is_program_code` = the program's own file (phase blocks,
  "is this class ours to declare"); `_cv_is_user_code` = that or a followed file
  (what gets translated). Mixing them up made followed classes non-external and
  POSIX's BEGIN blocks the program's.
- **Wire:** `modules` = [{name, file}]; a followed sub's method entry carries `module`;
  a followed package/class is `external`. An imported alias call names the CV's home.
- **Deparse:** owns every `module`-tagged graph (and bodies lifted from it); the
  source's `use` loads it.
- **chalk:** from_json loads only reachable graphs (`_reachable_methods`): the
  program's own graphs, plus module subs called by name, by a method call on a
  named class (resolved through its parent chain), or by a method name on an
  unknown invocant. Without that, POSIX's AUTOLOAD made every stash read GAP and
  T2 refused the whole program.
- **Exposed bug fixed:** Context's class-derived LLVM names (`%Foo::Bar.vt`) are
  now quoted; a program's own `package Foo::Bar` broke on that path too.

**Why:** perigrin wants imports followed the way other languages follow them.
**How to apply:** a new failure after a program `use`s something: ask whether the
module's code is reached, then whether it is a builtin's module.
- **XS (done, 2026-11-10):** under O, B::SoN wraps XSLoader::load and
  DynaLoader::bootstrap when it loads (O calls compile() at CHECK, too late) and
  restores them in compile(). A load inside the module's own eval (an eval frame
  met before its require frame; `$^S` is no help, it is true inside any require)
  dies with PerlOnJava's wording, so the fallback loads (Data::Dumper ->
  $Useperl). A bare load (POSIX) loads; its calls carry `xs`; T2 refuses
  "<name> is XS".
- **Preloaded modules (done):** a module already in %LOADED_INC (Carp,
  Exporter, Scalar::Util) is followed when a saved BEGIN (a `use`) in the
  program or a followed file requires it (`_required_files`). shortcut: a
  preloaded module's own uses ran before save_BEGINs, so its deps follow only
  if named elsewhere.
- **A module's refusals ride the wire:** B::SoN prints GAPs for the program's
  own subs only; a followed module's go into `refused` {name => GAP}. Bodies
  lifted from a module sub (`M::g::__SUBSTREPL__:1`) carry `module` too --
  untagged, Carp's became program seeds and dragged POSIX::import in.
- **chalk reach is SURE or MAYBE:** program graphs, direct calls, named-class
  method calls and lifted bodies are sure; a method name on an unknown invocant
  only may. A sure reach of a refused sub refuses the program in the module's
  words; a maybe never does (pvm does not read this wire: additive keys are
  safe).
- **Exporter (done):** `use Foo qw(f)` with Foo on Exporter follows Foo and
  Exporter; Exporter's subs are pruned (nothing sure calls them); the call
  names Foo::f; deparse leaves both to the `use`.
- **Run-time `require $x` (done):** refused as "a require of a name computed
  at run time is not followed" (chalk Context's require lowering; T2 declines
  any require). Milestone 1 closed 2026-11-10.
Stays a GAP (perigrin, 2026-11-11: "runtime require Foo is gonna remain a gap
for now"): a literal `require Foo` that runs after CHECK is not followed. Also
not loaded: module subs reached only by a computed name.
