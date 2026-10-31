my $x = 0; my $s = "";
while (1) { $s .= "a" if $x < 2; $x = $x + 1; last if $s eq "aa" && $x > 4 }
print "f $x $s\n";
