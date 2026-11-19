### lo2
```perl
our $g = 1; sub t { local $g = 2; die "x\n" } eval { t() }; print "$g\n";
```
perl: `1\n`  
chalk: `2\n`

### lo3
```perl
our $g = 1; for my $i (1..2) { local $g = $g + $i; last if $i == 2 } print "$g\n";
```
perl: `1\n`  
chalk: `4\n`

### lo16
```perl
our $v = 1; sub show { print $v } sub t { local $v = 2; show(); eval { local $v = 3; show(); die "x\n" }; show() } t(); show(); print "\n";
```
perl: `2321\n`  
chalk: `2331\n`

