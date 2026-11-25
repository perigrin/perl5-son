# ABOUTME: A followed module for t/a-followed-modules-start-state.t: its file-level code sets package
# ABOUTME: variables (a number, a string, an array, a reference) that perl runs at `use` time.
package K9::Mod;
our $n = 1;
our $s = "a\"b";
our $u;
our @l = (1, 2);
our $r = [1];
sub bump { $n++; return }
sub get  { $n }
1;
