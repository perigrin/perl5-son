my $pattern = $ENV{X} // "*.nonexistent-xyz";
my @none = glob $pattern;
my $cmd = $ENV{X} // "echo hi";
my $out = readpipe $cmd;
print "got ", scalar(@none), " ", $out;
