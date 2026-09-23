# Regex -- a compiled qr// object as a value
my $re = qr/\d+/;
my $text = "abc123";
print(($text =~ $re) ? "match\n" : "no\n");
print ref($re), "\n";
