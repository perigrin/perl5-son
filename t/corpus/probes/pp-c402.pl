my $calls = 0;
sub fallback { $calls++; return 7 }
my $out = "";
for my $x (undef, 2, undef) {
    my $v = $x // fallback();
    $out .= $v;
}
print "$out $calls\n";
