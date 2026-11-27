our ($x, $y); sub z { local $x = 9; 0 } my @l = ((($x, $y) = (7,8)), z()); print "@l\n";
