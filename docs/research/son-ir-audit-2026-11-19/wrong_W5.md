### cl23
```perl
my $x = 1; my $g = sub { $x }; sub setx { $_[0] = 12 } setx($x); print $g->(), "\n";
```
perl: `12\n`  
chalk: `1\n`

### ar21
```perl
my $x = 1; my $g = sub { $x }; my $set = sub { $_[0] = 5 }; $set->($x); print $g->(), "\n";
```
perl: `5\n`  
chalk: `1\n`

### ar22
```perl
my $c = 0; my $g = sub { $c }; sub bump { $_[0]++ } bump($c) for 1..3; print $g->(), "\n";
```
perl: `3\n`  
chalk: `0\n`

