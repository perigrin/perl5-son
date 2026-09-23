# Match (the =~ binding itself, distinct from RegexMatch)
my $text = "foo123bar";
my $re = qr/(\d+)/;
if ($text =~ $re) { print "got $1\n" }
my @all = ($text =~ /([a-z]+)/g);
print "@all\n";
print(($text !~ /zzz/) ? "nomatch\n" : "match\n");
