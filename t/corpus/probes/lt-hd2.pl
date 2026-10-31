package F { sub new { bless { n => { a => 1, b => 2 } }, shift } } my $f = F->new; print join(",", sort keys $f->{n}->%*), "\n";
