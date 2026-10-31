package S { sub new { bless { n => $_[1] }, $_[0] } sub name { $_[0]{n} } }
sub subs { (S->new("a"), S->new("b")) }
my @s = subs(); print scalar(@s), " ", $s[1]->name, "\n";
