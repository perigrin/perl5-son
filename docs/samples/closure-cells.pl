# ABOUTME: The source behind docs/samples/closure-cells.json -- three capture shapes.
# ABOUTME: perl prints 611 then 622; the second line is what a snapshot design gets wrong.
use 5.42.0;

my $n = 5;
my $get = sub { $n + 1 };          # read-only capture

my $c = 0;
my $inc = sub { $c = $c + 1 };     # captured AND written (a TARGMY add, no sassign)
my $rd  = sub { $c };              # SAME cell as $inc -- sharing

print $get->(), $inc->(), $rd->(), "\n";   # 611
print $get->(), $inc->(), $rd->(), "\n";   # 622 -- $inc mutates per call
