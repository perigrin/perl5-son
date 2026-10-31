my $f = { n => { a => 1, b => 2 } }; print join(",", sort keys $f->{n}->%*), "\n";
