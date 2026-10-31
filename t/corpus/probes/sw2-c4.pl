my $t = 0; my $add = sub { $t += $_[0] }; if (@ARGV == 0) { $add->(5) } print "$t\n";
