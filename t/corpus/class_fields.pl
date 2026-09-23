# FieldAccess (class feature field reads), Parameter (signature params)
use v5.42.0;
use experimental 'class';

class Point {
    field $x :param = 0;
    field $y :param = 0;
    method sum ($bias = 0) { return $x + $y + $bias }
    method show () { return "($x,$y)" }
}

my $p = Point->new(x => 3, y => 4);
print $p->show, "\n";
print $p->sum, "\n";
print $p->sum(10), "\n";
