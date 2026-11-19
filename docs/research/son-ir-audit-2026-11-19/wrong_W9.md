### fl11
```perl
my $h = { a => 1 }; my $v = $h->{b}{c}; print exists $h->{b} ? "viv" : "none", "\n";
```
perl: `viv\n`  
chalk: `none\n`

