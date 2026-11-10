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
Next: modules the
compiler preloaded (Carp, Scalar::Util) are not followed yet, Exporter as a real module.
