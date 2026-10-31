my $s = "a b"; (my $t = $s) =~ s/ (\w)/_\U$1/; print "$t\n";
