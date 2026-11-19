### nv1
```perl
our @st = (1); my @c = (@st, 2); @st = (); print "@c\n";
```
perl: `1 2\n`  
chalk: `2\n`

### nv4
```perl
our @g = (1,2); my @c = (0, @g); @g = (7); print "@c|@g\n";
```
perl: `0 1 2|7\n`  
chalk: `0 7|7\n`

### nv5
```perl
our %g = (a => 1); my @k = (%g); %g = (); print scalar(@k), "\n";
```
perl: `2\n`  
chalk: `0\n`

### nv7
```perl
our @g = (1,2); sub cp { my @c = (@g, 0); @g = (); return scalar @c } print cp(), scalar(@g), "\n";
```
perl: `30\n`  
chalk: `10\n`

### nv8
```perl
our @g = (1); sub t { local @g = (@g, 2); return scalar @g } print t(), scalar(@g), "\n";
```
perl: `21\n`  
chalk: `11\n`

### lo14
```perl
our @st = (1); sub t { local @st = (@st, 2); return scalar @st } print t(), scalar(@st), "\n";
```
perl: `21\n`  
chalk: `11\n`

