sub bump { $_ .= "!" }
sub f { my @a = (1, 2); $_ = "top"; bump() for @a; return "$_|@a" }
print f(), "\n";
