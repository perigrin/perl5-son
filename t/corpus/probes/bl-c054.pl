package Foo;
sub hi { return "hi" }
package main;
my $o = bless {}, "Foo";
print $o->hi, "\n";
