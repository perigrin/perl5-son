### bless2
```perl
my $h = {}; my $o = bless $h, "K"; print ref($h), " ", ref($o), "\n";
```
perl: `K K\n`  
chalk: `HASH K\n`

### ef9
```perl
my $o = {}; my $c = ref($o); bless $o, "K"; my $d = ref($o); print "$c $d\n";
```
perl: `HASH K\n`  
chalk: `K K\n`

### ef10
```perl
my $o = bless {}, "A"; my $c1 = ref $o; my $p = bless $o, "B"; print "$c1 ", ref($o), "\n";
```
perl: `A B\n`  
chalk: `A A\n`

### st2
```perl
use Scalar::Util qw(blessed); my $o = {}; my $a = blessed($o) // "u"; bless $o, "K"; my $b = blessed($o) // "u"; print "$a $b\n";
```
perl: `u K\n`  
chalk: `K K\n`

### st6
```perl
my $o = bless {}, "A"; my $a = ref($o); my $q = $o; bless $q, "B"; print "$a ", ref($o), "\n";
```
perl: `A B\n`  
chalk: `B B\n`

### st7
```perl
sub mk { return bless {}, "A" } sub re { bless $_[0], "B"; return } my $o = mk(); my $a = ref($o); re($o); print "$a ", ref($o), "\n";
```
perl: `A B\n`  
chalk: `B B\n`

### st14
```perl
my $f = sub { 1 }; my $a = ref($f); my $h = {}; my $b = ref($h); bless $h, "Z"; print "$a $b ", ref($h), "\n";
```
perl: `CODE HASH Z\n`  
chalk: `CODE Z Z\n`

### vp19
```perl
my $o = {}; my @r = (ref($o), ref(bless $o, "K"), ref($o)); print "@r\n";
```
perl: `HASH K K\n`  
chalk: `HASH K HASH\n`

