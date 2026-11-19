### ca29
```perl
my @o; sub DESTROY { push @o, "d" } { my $x = bless [], "main"; } print "@o\n";
```
perl: `d\n`  
chalk: `\n`

### im6
```perl
my @o; package D; sub new { bless {}, shift } sub DESTROY { push @o, "d" } package main; my $x = D->new; undef $x; print "@o\n";
```
perl: `d\n`  
chalk: `\n`

