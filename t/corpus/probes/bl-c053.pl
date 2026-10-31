my %a = (n => 1);
my $c = "Foo";
my $o = bless { %a }, $c;
print ref $o, "\n";
