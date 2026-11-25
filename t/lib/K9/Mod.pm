# ABOUTME: A followed module for t/a-followed-modules-start-state.t: its file-level code sets package
# ABOUTME: variables (a number, a string, an array, a reference) that perl runs at `use` time.
# (The object is K9::ModObj's: a bless is code beyond plain data -- audit 3, N9.)
package K9::Mod;
our $n = 1;
our $s = "a\"b";
our $u;
our @l = (1, 2);
our $r = [1];
our %h = (k => [1, 2]);
sub bump { $n++; return }
sub get  { $n }
1;
