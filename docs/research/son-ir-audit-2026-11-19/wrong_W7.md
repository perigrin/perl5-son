### fl1
```perl
my $d = @ARGV; my $q = 1 / $d; print "before\n"; print "$q\n";
```
perl: `` (exit 255)  
chalk: `before\n` (exit 255)

### fl6
```perl
my $d = @ARGV; my $q = 7 % $d; print "before\n"; print "$q\n";
```
perl: `` (exit 255)  
chalk: `before\n` (exit 255)

### fl5
```perl
use strict; my $r; print "a\n"; my @l = @$r; print "b\n";
```
perl: `a\n` (exit 255)  
chalk: `a\nb\n`

### ex1
```perl
eval { die { code => 7 } }; print ref($@), " ", (ref $@ ? $@->{code} : "str"), "\n";
```
perl: `HASH 7\n`  
chalk: ` str\n`

### ex2
```perl
eval { die [1,2] }; print ref($@) ? "ref" : "str", "\n";
```
perl: `ref\n`  
chalk: `str\n`

### ex3
```perl
package E; sub new { bless { m => $_[1] }, $_[0] } sub msg { $_[0]{m} } package main; eval { die E->new("oops") }; print ref($@) ? $@->msg : "str:$@", "\n";
```
perl: `oops\n`  
chalk: `str:E=HASH(0x..) at /tmp/claude-0/audit/p/ex3.pl line 1.\n\n`

### ex4
```perl
my $e; { local $@; eval { die { code => 7 } }; $e = $@ } print ref($e), "\n";
```
perl: `HASH\n`  
chalk: `\n`

### ev6
```perl
my $x = 1; { local $@; eval { $x = 5; die { code => 7 } }; $x += $@->{code} if ref $@ } print "$x\n";
```
perl: `12\n`  
chalk: `5\n`

