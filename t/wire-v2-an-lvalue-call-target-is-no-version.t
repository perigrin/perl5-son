# ABOUTME: An :lvalue sub called as an assignment's target (`slot() = 42`) is a call, on the chain
# ABOUTME: where it stands and a version, and the location the Assign after it stores through.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

# WHY. The call was pinned and made the memory version where it stood, then
# taken off the control chain to be the Assign's location: a version off
# the chain (V2, corpus 398), which chalk's loader invariant (L2) refuses.
# Then it was taken off both chains: a call that ran nowhere (audit 3,
# effect-floating). Now it stays where it was pinned, and the Assign
# follows it.
my $dir = tempdir( CLEANUP => 1 );
open my $o, '>', "$dir/p.pl" or die $!;
print $o q{my $slot = 0; sub slot :lvalue { $slot } slot() = 42; print slot(), "\n";};
close $o;
my $w = JSON::PP->new->utf8->decode( scalar qx($^X -Ilib -MO=-q,SoN,json,wire=2,not_package=SoN $dir/p.pl 2>/dev/null) );
my @nodes = $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
my %by = map { ( $_->{id} => $_ ) } @nodes;
my ($store) = grep { $_->{op} eq 'Assign' && ( $by{ $_->{inputs}[0] }{op} // '' ) eq 'Call' } @nodes;
ok $store, 'the store through the call is an Assign whose target is the Call';
my $call = $by{ $store->{inputs}[0] };
ok defined $call->{control_in}, 'the call is on the control chain';
ok $call->{mem_out}, '...and a memory version';
ok $store->{mem_out} && defined $store->{control_in}, 'the Assign is a version, on the chain';
is $store->{control_in}, $call->{id}, 'the Assign follows the call on control';
is $store->{mem_in}, $call->{id}, '...and on memory';
is [ grep { $_->{rule} =~ /\A(?:version-off-chain|memory-order-disagrees|write-unreachable|effect-floating)\z/ }
        SoN::Verify::verify($w)->{violations}->@* ], [], 'no V2, V2b, V3 or V5 violation';
done_testing;
