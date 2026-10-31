package Foo;
sub hi { return "hi" }
package main;
print Foo->hi, "\n";
