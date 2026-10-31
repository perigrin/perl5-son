my %h = (n => [1]); my @l = @{ $h{z} }; print scalar(@l), "|", join(",", @{ $h{z} }), "|", scalar(@{ $h{n} }), "|", join(",", @{ $h{n} }), "\n";
