# ABOUTME: tools/wire-verify.pl counts a wire the producer did not write (a compile
# ABOUTME: that failed or timed out) as #dropped, names it, and does not cache it.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use File::Path qw(make_path);

# A dropped wire used to take its violations out of every row in silence: a
# chalk module that ran past the timeout simply was not counted.
my $chalk = tempdir( CLEANUP => 1 );
my $wires = tempdir( CLEANUP => 1 );
make_path("$chalk/lib");
my %mod = (
    'Ok.pm'   => "package Ok; sub f { my \$x = shift; \$x + 1 } 1;\n",
    'Slow.pm' => "package Slow; BEGIN { sleep 30 } 1;\n",
    'Bad.pm'  => "package Bad; sub f { 1 \n",
);
for ( keys %mod ) { open my $o, '>', "$chalk/lib/$_" or die $!; print $o $mod{$_} }

local $ENV{SON_WIRE_TIMEOUT} = 5;
my $out = qx($^X tools/wire-verify.pl --tsv --chalk '$chalk' --wires '$wires' 2>&1);
like $out, qr/^chalk\t#dropped\t2$/m, 'two wires dropped';
like $out, qr/^dropped: chalk Slow\b/m, 'the timed-out one by name';
like $out, qr/^dropped: chalk Bad\b/m, 'the failed one by name';
like $out, qr/^chalk\t#wires\t1$/m, 'one wire written';
like $out, qr/^chalk\t\@Ok::f\t/m, 'its graphs are counted one by one';
like $out, qr/^chalk\t\@Ok:main::__PROGRAM__\t/m, 'a file graph is named by its wire';
ok !-e "$wires/chalk/Slow.json" && !-e "$wires/chalk/Bad.json", 'a dropped wire is not cached';

done_testing;
