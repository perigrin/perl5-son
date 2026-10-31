use v5.42; no warnings;
my %h;
sub g ($k, $x) { if ($k) { 1 } else { $h{$k} = 3; 2 } }
print g(1, "X"), g(0, "Y"), " $h{0}\n";
