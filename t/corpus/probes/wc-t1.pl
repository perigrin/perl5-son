my @v = ("0", "", "00", "a", "0.0", " ");
for my $x (@v) { print !$x ? "F" : "T" }
print "\n";
my %h = (z => 0, e => "", o => "0", t => "x");
for my $k (qw(z e o t n)) { print !$h{$k} ? "f" : "t" }
print "\n";
my $c = 0; my %n = (a => "b", b => "0"); my $cur = "a"; while (my $x = $n{$cur}) { $c++; $cur = $x } print "$c\n";
