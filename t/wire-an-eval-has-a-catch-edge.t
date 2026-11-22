# ABOUTME: Wire v2's `eval` profile: a die in a block eval leaves by an Exc, which carries the
# ABOUTME: restore of a `local` to the eval's catch Region; $@ is stored there; the join is plain.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# docs/plans/2026-11-20-wire-v2.md, section 3.5, node by node (as facts about
# the nodes, not their ids):
#
#   our $g = 1; eval { local $g = 2; die "x\n" }; print "$g $@";
#
# perl prints `1 x`. On the `mem` profile the eval's join took the local's
# store through the Unwind: no restore, no store of $@, nothing to stand on.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub wire ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return JSON::PP->new->utf8->decode( scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err) );
}
sub graph ( $w, $name = 'main::__PROGRAM__' ) {
    my @n = $w->{methods}{$name}{nodes}->@*;
    return ( \@n, { map { $_->{id} => $_ } @n } );
}
sub f ( $x, $k ) { ( $x->{fields} // {} )->{$k} }
sub is_g ( $x, $sym ) { $x && $x->{op} eq 'EntryDef' && ( f( $x, 'symbol' ) // '' ) eq $sym }

my $w = wire(q{our $g = 1; eval { local $g = 2; die "x\n" }; print "$g $@";});
ok( ( grep { $_ eq 'eval' } $w->{profile}->@* ), 'the wire says it obeys the eval profile' );
my ( $nodes, $by ) = graph($w);

my ($die) = grep { $_->{op} eq 'Unwind' } @$nodes;
my @exc   = grep { $_->{op} eq 'Exc' } @$nodes;
is scalar @exc, 1, 'one Exc: the die is the one thing in the body that may die';
is $exc[0]{inputs}, [ $die->{id} ], '... the Unwind\'s way out';

my @after = grep { ( $_->{control_in} // -1 ) == $exc[0]{id} } @$nodes;
is scalar @after, 1, 'one node stands on the edge';
my $restore = $after[0];
is $restore->{op}, 'EntryWrite', '... a store';
ok is_g( $by->{ $restore->{inputs}[0] }, 'g' ), '... of $g';
my $saved = $by->{ $restore->{inputs}[1] };
ok is_g( $saved, 'g' ), '... of $g\'s value read';
my ($local) = grep { $_->{op} eq 'EntryWrite' && $_->{id} == $die->{mem_in} } @$nodes;
ok $local && is_g( $by->{ $local->{inputs}[0] }, 'g' ), 'the die follows the local\'s store';
is $saved->{mem_in}, $local->{mem_in}, '... and the value put back is read where the local stores over it';
is $restore->{mem_in}, $die->{mem_in}, 'the edge\'s memory is the die\'s';
ok $restore->{mem_out}, 'the restore is a version';

my ($catch) = grep { $_->{op} eq 'Region' && f( $_, 'catch' ) } @$nodes;
ok $catch, 'a catch Region' or return;
is $catch->{inputs}, [ $restore->{id} ], '... its one way in the edge\'s end';
is f( $catch, 'eval_id' ), f( $die, 'eval_id' ), '... of the die\'s eval';

my ($err) = grep { ( $_->{control_in} // -1 ) == $catch->{id} } @$nodes;
is $err->{op}, 'EntryWrite', 'after the catch, a store';
ok is_g( $by->{ $err->{inputs}[0] }, '@' ), '... to $@';
is $err->{inputs}[1], $exc[0]{id}, '... of the exception in flight (the Exc: one edge, no Phi)';
is $err->{mem_in}, $restore->{id}, '... after the restore';

my ($join) = grep { $_->{op} eq 'Region' && defined f( $_, 'eval_entry' ) } @$nodes;
is $join->{inputs}, [ $err->{id} ], 'the join: its one way in the catch\'s (the body always dies)';
ok !( grep { $_->{op} eq 'Phi' && f( $_, 'region' ) == $join->{id} } @$nodes ), '... with no Phi (one way in)';
my ($read) = grep { is_g( $_, 'g' ) && ( $_->{mem_in} // -1 ) == $err->{id} } @$nodes;
ok $read, 'the read of $g after the eval is at the $@ store, after the restore';
my ($ret) = grep { $_->{op} eq 'Return' } @$nodes;
is $ret->{mem_in}, $err->{id}, 'the Return names it too';

# AN EVAL THAT ENDS: its $@ is cleared at its end (perl does; the wire says so).
{
    my ( $n2, $by2 ) = graph( wire(q{our $g = 1; sub f { die "y\n" if $g > 5 } eval { f(); 1 }; print "[$@]\n";}) );
    my ($j) = grep { $_->{op} eq 'Region' && defined f( $_, 'eval_entry' ) } @$n2;
    my @in = map { $by2->{$_} } $j->{inputs}->@*;
    is scalar @in, 2, 'an eval whose body ends: two ways into its join, the end and the catch';
    my ($clear) = grep { $_->{op} eq 'EntryWrite' && is_g( $by2->{ $_->{inputs}[0] }, '@' ) && ( f( $by2->{ $_->{inputs}[1] }, 'value' ) // 'u' ) eq '' } @in;
    ok $clear, '... the end\'s last node the store of "" to $@';
    my ($call) = grep { $_->{op} eq 'Call' && ( f( $_, 'name' ) // '' ) eq 'main::f' } @$n2;
    my ($x) = grep { $_->{op} eq 'Exc' } @$n2;
    is $x->{inputs}, [ $call->{id} ], '... the call\'s Exc';
    my @phi = grep { $_->{op} eq 'Phi' && f( $_, 'region' ) == $j->{id} } @$n2;
    is [ map { scalar $_->{inputs}->@* } @phi ], [ map { 2 } @phi ], '... every Phi of the join with as many inputs as its ways in';
    ok( ( grep { f( $_, 'memory' ) } @phi ), '... one of them its memory' );
}
# A STORE THAT DIES WHERE IT STANDS (through a reference to a read-only
# value, or none): its target dies as the store is made, so the store has
# the way out -- the memory before it, the store not made.
{
    my ( $n3, $by3 ) = graph( wire(q{my @r = \(3); eval { ${$r[-1]} = 2 }; print $@ ? "ro\n" : "rw\n";}) );
    my ($st) = grep { $_->{op} eq 'Assign' && defined $_->{control_in} && ( $by3->{ $_->{inputs}[0] }{op} // '' ) eq 'PostfixDeref' } @$n3;
    ok $st, 'the store through the dereference' or last;
    my ($x) = grep { $_->{op} eq 'Exc' && $_->{inputs}[0] == $st->{id} } @$n3;
    ok $x, '... has its way out';
}
done_testing;
