sub f { (1,2,3) } sub g { () } my $c = () = f(); my $d = () = g(); print "$c $d\n";
