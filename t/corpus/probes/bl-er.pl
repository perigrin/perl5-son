my @a = (10, 20); my $r = \$a[1]; $$r = 5; print ${$r}, " $a[1]\n";
