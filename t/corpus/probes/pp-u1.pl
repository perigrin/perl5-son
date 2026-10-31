my $s = $ENV{S} // "aBc"; print uc($s), lc($s), ucfirst(lc $s), lcfirst($s), "\n";
