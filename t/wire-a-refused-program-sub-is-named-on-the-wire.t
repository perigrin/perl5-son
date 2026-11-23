# ABOUTME: A sub of the program B::SoN refuses is named in the wire's `refused`, as a followed
# ABOUTME: module's is, so a consumer that reaches it refuses by name instead of finding no method.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

# RE-AUDIT 2026-11-23, section 3 H: `package C; our $i; sub get { $i ||= 7 }
# package main; print C->get` -- get was refused (`||=` into a package
# scalar), only on stderr; chalk found no `get` in C and its program died
# "Can't locate object method "get" via package "C"", an error perl never
# gives.
my $f = "$dir/g.pl";
open my $fh, '>', $f or die $!;
print $fh q{package C; our $inst; sub get { $inst ||= 7 } package main; print C->get, "\n";};
close $fh;
my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
my $err  = do { local ( @ARGV, $/ ) = "$dir/err"; <> };
my $wire = JSON::PP->new->decode($json);
ok !exists $wire->{methods}{'C::get'}, 'C::get is not on the wire';
like $wire->{refused}{'C::get'}, qr/\AGAP: `\|\|=` into something other than/, 'it is in `refused`, by its GAP';
like $err, qr/B::SoN: skipped C::get: GAP:/, 'and still said on stderr';

done_testing;
