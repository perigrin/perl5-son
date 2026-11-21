# ABOUTME: `$x .= ...` on a `my` scalar kept in memory yields the variable read after its store:
# ABOUTME: on wire v2 that read names the store as its mem_in, never as a value input.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';

# WHY. One construction site still gave the read its memory as an input
# (`inputs => [$store]`, v1's shape): on wire v2 a PadAccess then had a value
# input that was a store, chalk took it for no location and refused probe
# ev10 (SAME on wire 1).
my $dir = tempdir( CLEANUP => 1 );
open my $o, '>', "$dir/p.pl" or die $!;
print $o q{use feature "try"; no warnings; my $x = 1; try { $x = 2; die "t\n"; $x = 3 } catch ($e) { $x .= "c" } print "$x\n";};
close $o;
my $w = JSON::PP->new->utf8->decode( scalar qx($^X -Ilib -MO=-q,SoN,json,wire=2,not_package=SoN $dir/p.pl 2>/dev/null) );
my @pad = grep { $_->{op} eq 'PadAccess' } $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
ok scalar(@pad), 'the program reads $x';
is [ map { $_->{id} } grep { ( $_->{inputs} // [] )->@* } @pad ], [], 'no PadAccess has a value input';
done_testing;
