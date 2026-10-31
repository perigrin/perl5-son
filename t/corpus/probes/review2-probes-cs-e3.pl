sub f { my $n = shift; my $r = $n // "dflt"; if ($r) { print "[$r]" } return 0 } f($ENV{CHALK_NOPE_XYZ}); print "\n";
