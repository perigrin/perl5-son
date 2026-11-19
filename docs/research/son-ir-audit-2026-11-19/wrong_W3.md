### dyn1
```perl
package C; sub new { bless {n=>0}, shift } sub inc { $_[0]{n}++; return }
package main; my $o = C->new; my $m = "inc"; $o->$m(); print $o->{n}, "\n";
```
perl: `1\n`  
chalk: `0\n`

### dyn2
```perl
package C; sub new { bless {n=>0}, shift } sub inc { $_[0]{n}++; return 5 }
package main; my $o = C->new; my $m = "inc"; my $r = $o->$m(); print "$r $o->{n}\n";
```
perl: `5 1\n`  
chalk: `5 0\n`

