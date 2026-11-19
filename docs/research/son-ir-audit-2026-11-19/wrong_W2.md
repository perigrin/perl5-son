### slice1
```perl
my %h; @h{qw(a b)} = (1,2); print "$h{a} $h{b}\n";
```
perl: `1 2\n`  
chalk: ` \n`

### slice2
```perl
my @a = (0,0,0); @a[0,1] = (5,6); print "@a\n";
```
perl: `5 6 0\n`  
chalk: `0 0 0\n`

### slice3
```perl
my %h = (a=>0); my @k = ("a","b"); @h{@k} = (7,8); print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";
```
perl: `a=7,b=8\n`  
chalk: `a=0\n`

### wa18
```perl
my @a = (1,2,3); my ($x, $y) = @a[0,1]; @a[0,1] = ($y, $x); print "@a\n";
```
perl: `2 1 3\n`  
chalk: `1 2 3\n`

### swap1
```perl
my @a = (1,2); ($a[0], $a[1]) = ($a[1], $a[0]); print "@a\n";
```
perl: `2 1\n`  
chalk: `1 2\n`

### swap3
```perl
my %h = (a=>1, b=>2); ($h{a}, $h{b}) = ($h{b}, $h{a}); print "$h{a} $h{b}\n";
```
perl: `2 1\n`  
chalk: `1 2\n`

### la2
```perl
my $r = [0,0]; ($r->[0], $r->[1]) = (3,4); print "@$r\n";
```
perl: `3 4\n`  
chalk: `0 0\n`

### la3
```perl
our @g = (0,0); ($g[0], $g[1]) = (3,4); print "@g\n";
```
perl: `3 4\n`  
chalk: `0 0\n`

### la5
```perl
my %h; my ($k, $v) = ("a", 1); ($h{$k}) = ($v); print "$h{a}\n";
```
perl: `1\n`  
chalk: `\n`

### la6
```perl
my @a = (0,0); my $i = 0; ($a[$i++], $a[$i++]) = (8,9); print "@a $i\n";
```
perl: `8 9 2\n`  
chalk: `0 0 2\n`

### ar12
```perl
sub f { @_ = (9, 9); $_[0] = 3 } my $x = 1; f($x); print "$x\n";
```
perl: `1\n`  
chalk: `3\n`

### cl15
```perl
my %h = (a => 1); my $g = sub { join ",", map { "$_$h{$_}" } sort keys %h }; $h{b} = 2; ($h{c}) = (3); print $g->(), "\n";
```
perl: `a1,b2,c3\n`  
chalk: `a1,b2\n`

### cl1
```perl
my $x = 1; my $g = sub { $x }; ($x) = (7); print $g->(), "\n";
```
perl: `7\n`  
chalk: `1\n`

### cl2
```perl
my $x = 1; my $g = sub { $x }; my @l = (7, 8); ($x) = @l; print $g->(), "\n";
```
perl: `7\n`  
chalk: `1\n`

### cl25
```perl
my $x = 5; my $g = sub { $x }; my $s = "v=5"; ($x) = $s =~ /(\d)/ ? 6 : 0; print $g->(), "\n";
```
perl: `6\n`  
chalk: `5\n`

