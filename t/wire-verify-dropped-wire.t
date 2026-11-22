# ABOUTME: tools/wire-verify.pl counts a wire the producer did not write (a compile
# ABOUTME: that was killed, timed out, or wrote no JSON) as #dropped, names it, and does not cache it.
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
    'Killed.pm' => "package Killed; BEGIN { kill 'KILL', \$\$ } 1;\n",
    # perl rejects it, and B::SoN still writes a wire (of what compiled): that
    # is a wire, as it always was -- chalk's Node/*.pm, compiled alone, are.
    'Bad.pm'  => "package Bad; sub g { 2 } sub f { 1 \n",
);
for ( keys %mod ) { open my $o, '>', "$chalk/lib/$_" or die $!; print $o $mod{$_} }

local $ENV{SON_WIRE_TIMEOUT} = 5;
my $out = qx($^X tools/wire-verify.pl --tsv --chalk '$chalk' --wires '$wires' 2>&1);
like $out, qr/^chalk\t#dropped\t2$/m, 'two wires dropped';
like $out, qr/^dropped: chalk Slow\b/m, 'the timed-out one by name';
like $out, qr/^dropped: chalk Killed\b/m, 'the killed one by name';
unlike $out, qr/^dropped: chalk Bad\b/m, 'a program perl rejects, with a wire written, is not dropped';
like $out, qr/^chalk\t#wires\t2$/m, 'two wires written';
# (stage 10: no per-graph lines -- every rule is hard, a violation is printed
# by name -- but the graphs of the wires written are counted)
like $out, qr/^chalk\t#graphs\t[1-9]\d*$/m, 'their graphs are counted';
ok !-e "$wires/chalk/Slow.json" && !-e "$wires/chalk/Killed.json", 'a dropped wire is not cached';

done_testing;
