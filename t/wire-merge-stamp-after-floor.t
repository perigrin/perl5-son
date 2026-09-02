# ABOUTME: A merge Phi must be re-asked AFTER the floor passes -- its inputs may
# ABOUTME: not be typed yet the first time the question is put.

use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;
use SoN::IR::Stamp;

my $PERL = $^X;
my $RS   = '/home/perigrin/dev/perl5/t/base/rs.t';

plan skip_all => "perl source tree not present at $RS" unless -r $RS;

# WHY THE FIXTURE IS rs.t. The defect needs a merge whose arm is typed only by
# a LATER pass, and that dependency does not arise in a small snippet: the arm
# here is an arithmetic Add over a package global, which `_floor_package_globals`
# types several passes after the merge is first considered.
#
# THE DEFECT IS PASS ORDERING, not the merge rule. `_stamp_merges` already
# implements the right rule and already runs -- in the FIRST fixpoint loop,
# which settles after two rounds while the Add input is still Unknown. It
# correctly declines. `_stamp_derived` then types that Add `Num` inside the
# SECOND loop, which never re-asks the merge. So the graph ends with both
# inputs narrowed (Add/Num, Constant/Str) and the Phi still Unknown.
#
# join(Num,Str) = Str, because Num descends from Str.

my $json = qx{$PERL -Ilib -MO=SoN,json $RS 2>/dev/null};
my $w = length($json) ? JSON::PP->new->decode($json) : undef;

subtest 'no merge is left Unknown once its arms are typed' => sub {
    ok $w, 'rs.t translates' or return;

    my %by = map { $_->{id} => $_ }
        map { ( $w->{methods}{$_}{nodes} // [] )->@* }
        keys( ( $w->{methods} // {} )->%* );

    my @stale;
    for my $n ( values %by ) {
        next unless ( $n->{op} // '' ) eq 'Phi';
        next unless ( $n->{stamp} // '' ) eq 'Unknown';
        my @in = map { $by{$_} } ( $n->{inputs} // [] )->@*;
        # Only a Phi whose arms are ALL typed is a defect: an Unknown arm
        # poisons the join honestly, and that rule must stay.
        next if grep { !$_ || ( $_->{stamp} // 'Unknown' ) eq 'Unknown' } @in;
        push @stale, sprintf( '%s<-[%s]', $n->{id},
            join( ',', map { $_->{stamp} } @in ) );
    }
    is scalar(@stale), 0,
        'every Phi with fully-typed arms carries their join'
        or diag( "stale: @stale" );
};

# THE POISONING RULE IS UNTOUCHED -- an Unknown arm still yields Unknown, and
# that is the lattice's answer rather than a special case.
subtest 'an Unknown arm still poisons the join' => sub {
    is SoN::IR::Stamp::join(
        SoN::IR::Stamp->new( type => 'Int' ),
        SoN::IR::Stamp->new( type => 'Unknown' ),
    )->type, 'Unknown', 'join(Int,Unknown) is Unknown';
};

done_testing;
