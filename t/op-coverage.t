# ABOUTME: Every node kind the producer can emit must be produced by some
# ABOUTME: fixture in t/corpus, or be a documented exemption.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# WHY THIS EXISTS. A node kind can ship, reach the wire, and be consumed by
# chalk with NOTHING in the suite producing one. Measured 2026-09-23 against
# an external 986-file corpus: thirteen kinds appeared there that no fixture
# of ours had ever produced -- DefinedOr (23 occurrences), Parameter (22),
# Chomp (18), Modulo (15), Wantarray (10), Negate (8), Complement (6),
# Divide (6), FieldAccess (4), Power (4), IsaOp (2), StrCmp (1), StrGe (1).
#
# FieldAccess is the sharp one: `class` feature field access, the newest part
# of the IR, with zero evidence behind it.
#
# This gate measures REACH, not correctness. A Divide appearing proves we emit
# a Divide, not that we emit the right one -- the round trips do that. What it
# stops is a node kind shipping with no fixture at all.
#
# Modelled on t/op-declaration-sites-agree.t, which does the same for type
# signatures, including its rule: an exemption with a reason is a design fact,
# an exemption without one is a TODO in disguise.

my $dir = tempdir( CLEANUP => 1 );

# THE DENOMINATOR: what the producer can construct. Two paths, because
# control-flow nodes never appear in OpMap -- they are built directly.
sub producer_can_emit () {
    my %node;
    open my $fh, '<', 'lib/SoN/FromOptree/OpMap.pm' or die "open OpMap: $!";
    while (<$fh>) { $node{$1}++ if /=> \[\s*[^,]+,\s*'(\w+)'/ }
    open my $fo, '<', 'lib/SoN/FromOptree.pm' or die "open FromOptree: $!";
    while (<$fo>) { $node{$1}++ while /make(?:_cfg)?\(\s*'(\w+)'/g }
    return grep { /\A[A-Z]/ } sort keys %node;
}

# THE NUMERATOR: what t/corpus actually produces.
sub ops_in_corpus () {
    my %seen;
    for my $f (sort glob 't/corpus/*.pl') {
        my $json = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
        my $data = eval { JSON::PP->new->decode($json) } or next;
        for my $m (values %{ $data->{methods} // {} }) {
            $seen{ $_->{op} }++ for @{ $m->{nodes} // [] };
        }
    }
    return %seen;
}

# (a) CONSTRUCTED ONLY BY A CONSUMER OR A PASS WE DO NOT RUN HERE. Not a
# producer output for any Perl program, so no fixture can produce one.
my %NOT_PRODUCER_OUTPUT = map { $_ => 1 } qw(
);

# (b) NEEDS A FIXTURE, none written yet. A TODO with a name on it. Anything
# listed here is work, not a design fact.
my %NO_FIXTURE_YET = map { $_ => 1 } qw(
);

subtest 'every node the producer can emit is produced by a fixture' => sub {
    my %seen = ops_in_corpus();
    my @unreached = grep {
        !$seen{$_} && !$NOT_PRODUCER_OUTPUT{$_} && !$NO_FIXTURE_YET{$_}
    } producer_can_emit();
    diag("  no fixture produces: $_") for @unreached;
    is( \@unreached, [], 'no node kind ships without a fixture' );
};

# THE EXEMPTION LISTS MUST NOT ROT, the same guard the signature test carries.
# A kind that gains a fixture should leave the list, or the list becomes where
# unmeasured nodes hide.
subtest 'the exemption lists contain only kinds that need to be there' => sub {
    my %seen = ops_in_corpus();
    my @stale = grep { $seen{$_} }
        ( sort keys %NOT_PRODUCER_OUTPUT, sort keys %NO_FIXTURE_YET );
    diag("  now HAS a fixture, drop from the exemption list: $_") for @stale;
    is( \@stale, [], 'no exempted kind has quietly gained a fixture' );
};

done_testing;
