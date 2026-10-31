package Foo; sub new { bless { v => $_[1] }, $_[0] } sub v { $_[0]{v} } package main; my $o = Foo->new(3); print $o->v, " ", ref($o), "\n";
