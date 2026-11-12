# ABOUTME: An endless loop (`for (;;)`, `while (1)`) in an else arm is a cycle of
# ABOUTME: ->next ops: a scan along the arm must stop where it has been, not spin.

use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

# File::Path::_rmtree has this shape; every program that loads File::Path hung.
for my $src (
    q{my $n = 0; if ($ARGV[0]) { $n++ } else { for (;;) { last } } print "$n\n";},
    q{my $n = 0; if ($ARGV[0]) { $n++ } else { for (;;) { $n += 2; last } } print "$n\n";},
    q{my $n = 0; if ($ARGV[0]) { $n++ } else { while (1) { $n += 2; last } } print "$n\n";},
) {
    my $f = "$dir/p." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    qx(/usr/bin/timeout 20 $^X -Ilib -MO=-q,SoN,json $f >/dev/null 2>$dir/err);
    my $rc = $? >> 8;
    isnt $rc, 124, "the producer finishes: $src";
    open my $eh, '<', "$dir/err" or die $!; my $err = do { local $/; <$eh> };
    unlike $err, qr/INTERNAL ERROR/, '... without an internal error';
}

done_testing;
