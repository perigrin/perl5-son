sub f { my $n = shift; if (defined $n) { print "def\n" } else { print "undef\n" } return 0 } f($ENV{CHALK_NOPE_XYZ}); f($ENV{HOME});
