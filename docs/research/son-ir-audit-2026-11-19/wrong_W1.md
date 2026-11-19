### pg1
```perl
our $g = 0; sub bump { $g += 10 } for my $i (1..3) { $g = $g + 1; bump(); } print "$g\n";
```
perl: `33\n`  
chalk: `13\n`

### pg2
```perl
our $g = 0; my $s = ""; sub bump { $g += 10 } for my $i (1..3) { $g = $g + 1; bump(); $s .= "$g," } print "$s\n";
```
perl: `11,22,33,\n`  
chalk: `1,2,3,\n`

### pl4
```perl
our $g = 0; sub bump { $g += 10 } my $i = 0; while ($i < 3) { $i++; $g = $g + 1; bump(); } print "$g\n";
```
perl: `33\n`  
chalk: `13\n`

### pl5
```perl
our $g = 0; sub bump { $g += 10 } for my $i (1..3) { $g++; bump(); } print "$g\n";
```
perl: `33\n`  
chalk: `13\n`

### pl6
```perl
our $g = 0; sub bump { $g += 10 } for my $i (1..3) { bump(); $g = $g + 1; } print "$g\n";
```
perl: `33\n`  
chalk: `3\n`

### pl8
```perl
our $g = 0; package O; sub new { bless {}, shift } sub hit { $main::g += 10 } package main; my $o = O->new; for my $i (1..3) { $g = $g + 1; $o->hit; } print "$g\n";
```
perl: `33\n`  
chalk: `13\n`

### pl10
```perl
our $n = 0; sub step { $n++ < 3 } my $t = 0; while (step()) { $t += $n; $n = $n + 0 } print "$t $n\n";
```
perl: `6 4\n`  
chalk: `(never ends: stopped after 20 s)`

### pl11
```perl
our $g = 0; sub bump { $g += 10 } for my $i (1..3) { $g = $g + 1; if ($i > 1) { bump() } } print "$g\n";
```
perl: `23\n`  
chalk: `13\n`

### tp5
```perl
our $depth = 0; sub walk { my $n = shift; $depth++; walk($n - 1) if $n > 0; return } for my $k (1..2) { $depth = $depth + 0; walk($k) } print "$depth\n";
```
perl: `5\n`  
chalk: `3\n`

### tp6
```perl
our $total = 0; sub add { $total += $_[0] } for my $x (1..4) { add($x); $total = $total * 1 } print "$total\n";
```
perl: `10\n`  
chalk: `0\n`

### tp7
```perl
our $s = ""; sub ap { $s .= $_[0] } for my $c ("a".."c") { $s .= "-"; ap($c) } print "$s\n";
```
perl: `-a-b-c\n`  
chalk: `-a\n`

