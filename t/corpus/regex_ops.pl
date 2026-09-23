# Match, RegexMatch, RegexCapture, RegexSubst, RegexSubstCount, Transliterate
my $s = "hello world";
print(($s =~ /world/) ? "m" : "x", "\n");
if ($s =~ /(\w+)\s+(\w+)/) { print "$1-$2\n" }
(my $t = $s) =~ s/world/perl/;
print "$t\n";
my $u = "aaa";
my $count = ($u =~ s/a/b/g);
print "$count $u\n";
my $v = "hello";
(my $w = $v) =~ tr/a-z/A-Z/;
print "$w\n";
my $n = ($v =~ tr/l//);
print "$n\n";
