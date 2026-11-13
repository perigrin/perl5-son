# ABOUTME: A .pl file the program requires (perl's own t/test.pl, `require './test.pl'`)
# ABOUTME: is followed as a module is: its subs are compiled with the program.
use 5.42.0;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $dir = tempdir( CLEANUP => 1 );
open my $pl, '>', "$dir/lib.pl" or die $!;
print $pl "sub twice { return 2 * shift }\nsub greet { return 'hi ' . shift }\n1;\n";
close $pl;
open my $fh, '>', "$dir/p.pl" or die $!;
print $fh "BEGIN { chdir '$dir'; require './lib.pl'; }\nprint twice(21), ' ', greet('x'), \"\\n\";\n";
close $fh;
my $w = decode_json( scalar qx($^X -Ilib -MO=-q,SoN,json $dir/p.pl 2>/dev/null) );
ok $w->{methods}{'main::twice'}, 'the required file\'s sub is on the wire';
ok $w->{methods}{'main::greet'}, '... each of them';
done_testing;
