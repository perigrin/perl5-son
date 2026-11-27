our $s = "abc"; sub ed { substr($s, 0, 1) = "z"; 1 } my @l = ($s, ed(), $s); print "@l\n";
