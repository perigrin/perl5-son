sub c { $a <=> $b }
my @r = @ARGV && sort c 3,1,2;
print scalar(@r), "\n";
