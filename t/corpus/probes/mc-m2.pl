package Foo;
sub new { bless {}, $_[0] }
sub hi { return "hi" }
package main;
my $o = Foo->new;
print $o->hi, "\n";
