# ABOUTME: _pin refuses, by name, a node that is already on the control chain elsewhere:
# ABOUTME: a hash-consed data node made in two arms and pinned in each is one node moved.
use v5.42.0;
use Test2::V0;
use SoN::FromOptree;
use SoN::FromOptree::StackSim;
use SoN::IR::NodeFactory;

# WHY. control_in is not in a node's content hash, so a DATA node that is
# `make`d and then pinned can come back from the cache already pinned: two
# arms reading `$st->{i}` at the same memory made one Subscript, the second
# _pin moved it into the second arm, and the first arm's store followed a node
# that was no longer in its arm (stage 1 of the wire v2 plan found it by the
# verifier's control-fork rule). Re-pinning moves the node silently; the
# guard makes it a refusal at build time.

my $f     = SoN::IR::NodeFactory->new;
my $start = $f->make_cfg('Start');
my $mem   = $f->make('MemStart');
my $other = $f->make_cfg('Region', inputs => [$start]);
my $c     = $f->make('ArrayLiteral', inputs => [], sigil => '@', symbol => 'a');
my $k     = $f->make('Constant', const_type => 'integer', value => 0);
my $read  = $f->make('Subscript', inputs => [ $c, $k, $mem ]);

my $sim1 = SoN::FromOptree::StackSim->new( control => $start, memory => $mem );
SoN::FromOptree::_pin( $sim1, $read );
is $read->control_in, $start, 'pinned once: follows the control it was pinned at';

my $sim2 = SoN::FromOptree::StackSim->new( control => $other, memory => $mem );
like dies { SoN::FromOptree::_pin( $sim2, $read ) },
    qr/\AGAP: .*already on the control chain/, 'pinned again elsewhere: refused by name';
is $read->control_in, $start, 'and not moved';

# Pinning where it already stands is no move (a handler may place what it pinned).
my $sim3 = SoN::FromOptree::StackSim->new( control => $start, memory => $mem );
ok lives { SoN::FromOptree::_pin( $sim3, $read ) }, 'pinned again at the same control: no move, no refusal'
    or note $@;

done_testing;
