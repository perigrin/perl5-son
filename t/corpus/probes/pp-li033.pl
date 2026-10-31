sub bare { return }
sub valued { return "v" }
my @empty = bare();
my @one   = valued();
my $scalar = bare();
print scalar(@empty), " ", scalar(@one), " ",
      (defined $scalar ? "def" : "undef"), "\n";
