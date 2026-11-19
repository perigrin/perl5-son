# ABOUTME: SoN::Verify -- the memory-chain rules checked on the wire itself: one
# ABOUTME: clean program, then one tiny program (or hand-built graph) per rule.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

# The audit (docs/research/son-ir-audit-2026-11-19/REPORT.md) found that memory
# is one chain and nothing checks it. Each program here is one of its probes,
# with the rule it breaks; the expectations are the audit's wire readings, not
# what the producer ought to emit. When a later step fixes the producer, the
# matching test here must move to "clean" -- and t/wire-verify-ratchet.t's
# baseline falls with it.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub wire ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    return JSON::PP->new->utf8->decode($json);
}

# rules($src_or_wire) -> { rule => [violation, ...] }
sub rules ($w) {
    $w = wire($w) unless ref $w;
    my %by;
    push $by{ $_->{rule} }->@*, $_ for SoN::Verify::verify($w)->{violations}->@*;
    return \%by;
}

sub ops ($list) { [ sort map { $_->{op} } @$list ] }

subtest 'a clean program: stores and reads in one chain' => sub {
    my $r = SoN::Verify::verify(
        wire('my @a = (1,2,3); $a[0] = 10; my $x = $a[0]; $a[1] = $x + 1; print "$a[0] $a[1]\n";') );
    is $r->{violations}, [], 'no violation'
        or diag explain_v( $r->{violations} );
};

# HAND-BUILT GRAPHS for the rules the producer does not break (any more): a
# rule with no failing case is a rule nobody has seen fail. A class the
# producer has since fixed keeps its rule tested here by hand, and its probe
# is asserted clean beside it.
sub graph (@nodes) {
    return { methods => { g => { returns => [ $nodes[-1]{id} ], nodes => \@nodes } } };
}
sub nd ( $id, $op, $in, %rest ) {
    my $ctl = delete $rest{ctl};
    return { id => $id, op => $op, inputs => $in, ( defined $ctl ? ( control_in => $ctl ) : () ),
        ( %rest ? ( fields => {%rest} ) : () ) };
}

# `@a[0,1] = (5,6)` as the producer made it until 2026-11-19: a slice Assign
# with no control_in and no reader.
sub floating_slice_assign () {
    return graph(
        nd( 0, 'Start', [] ), nd( 1, 'Constant', [] ), nd( 2, 'MemStart', [] ),
        nd( 3, 'PadAccess', [], sigil => '@', symbol => 'a' ),
        nd( 4, 'Slice', [ 1, 3 ], kind => 'array' ),
        nd( 5, 'Assign', [ 4, 1 ], targets => 1 ),
        nd( 6, 'Return', [1], ctl => 0 ),
    );
}

subtest 'every violation names its node, kind, rule and graph' => sub {
    my $r = rules( floating_slice_assign() );
    my ($v) = $r->{'write-floating'}->@*;
    is $v->{graph}, 'g',      'graph';
    is $v->{op},    'Assign', 'kind';
    like $v->{node}, qr/^\d+$/, 'node id';
    like $v->{detail}, qr/slice|element/, 'detail says what it writes';
};

subtest 'write-floating: a store with no control_in and no reader (slice2)' => sub {
    is ops( rules( floating_slice_assign() )->{'write-floating'} ), ['Assign'], 'the slice assign floats';
    # The producer places it now (t/wire-list-assign-places-by-storage.t).
    is rules('my @a = (0,0,0); @a[0,1] = (5,6); print "@a\n";')->{'write-floating'}, undef,
        'and the producer no longer makes one';
};

subtest 'effect-rides-value: a call off the chain (dyn1)' => sub {
    my $r = rules(<<'P');
package C; sub new { bless {n=>0}, shift } sub inc { $_[0]{n}++; return }
package main; my $o = C->new; my $m = "inc"; $o->$m(); print $o->{n}, "\n";
P
    my @dyn = grep { $_->{detail} =~ /dynamic_method/ } ( $r->{'write-floating'} // [] )->@*,
        ( $r->{'effect-rides-value'} // [] )->@*;
    is scalar(@dyn), 1, 'the dynamic method call is not on the chain';
    my @bless = grep { $_->{detail} =~ /bless/ } ( $r->{'effect-rides-value'} // [] )->@*;
    is scalar(@bless), 1, 'bless used for its value rides the value edge';
};

subtest q{s///r stores nothing: it is a value, not a floating write} => sub {
    my $r = rules(q{my $s = "a"; my $t = $s =~ s/a/b/r; print "$s $t\n";});
    is $r->{q{effect-rides-value}}, undef, q{not an effect};
    is ops( rules(q{my $s = "a"; print "x" if $s =~ s/a/b/; print "$s\n";})->{q{effect-rides-value}} // [] ),
        [], q{a destructive s/// in a condition is pinned};
};

subtest 'records and parameter binds float by design, and are counted' => sub {
    my $res = SoN::Verify::verify( wire(<<'P') );
sub f { my ($a, $b) = @_; return $a + $b }
sub new { my ($c, %o) = @_; return $o{ix} }
print f(1, 2), main->new(ix => 3), "\n";
P
    is [ grep { $_->{rule} =~ /^write-|^effect-/ } $res->{violations}->@* ], [], 'none is a violation';
    ok $res->{allowed}{record} >= 1, 'my ($a, $b) = @_ is a record';
    ok $res->{allowed}{'param-bind'} >= 1, 'my ($c, %o) = @_ is a parameter bind';
};

subtest 'read-unversioned:object-class: ref() either side of a bless (ef9)' => sub {
    my $r = rules('my $o = {}; my $c = ref($o); bless $o, "K"; my $d = ref($o); print "$c $d\n";');
    is ops( $r->{'read-unversioned:object-class'} ), ['RefType'], 'one RefType, no memory input';
};

subtest 'read-unversioned:package-aggregate-literal: a flattened package array (nv1)' => sub {
    my $r = rules('our @st = (1); my @c = (@st, 2); @st = (); print "@c\n";');
    ok scalar( ( $r->{'read-unversioned:package-aggregate-literal'} // [] )->@* ),
        '@st read through its named literal';
};

subtest 'read-unversioned:package: a package scalar read at no version' => sub {
    my $r = rules(<<'P');
our $total = 0;
sub tally { for my $x (@_) { if ($x > 2) { $total += $x } } return $total }
print tally(1, 3, 5), "\n";
P
    is ops( $r->{'read-unversioned:package'} ), ['EntryDef'], '$total += reads $total with no memory';
};

subtest 'phi-arity:eval-join: the eval join has one way in, two-input Phis' => sub {
    my $r = rules('my $x = 1; my $r = eval { $x = 2; die "a\n" if @ARGV; 5 }; print "$x $r $@\n";');
    is ops( $r->{'phi-arity:eval-join'} ), ['Phi'], 'the value Phi of the eval';
    is $r->{'phi-arity'}, undef, 'and it is not counted as an unknown mismatch';
};

subtest 'fault-floating: a division that may die has no control (fl1)' => sub {
    my $r = rules('my $d = @ARGV; my $q = 1 / $d; print "before\n"; print "$q\n";');
    is ops( $r->{'fault-floating'} ), ['Divide'], 'Divide floats';
    is rules('my $d = @ARGV; my $q = $d / 2; print "$q\n";')->{'fault-floating'}, undef,
        'a constant non-zero divisor cannot fault';
};

subtest 'package-scalar-loop-value: $g carried round a loop as a value (pg1)' => sub {
    my $r = rules('our $g = 0; sub bump { $g += 10 } for my $i (1..3) { $g = $g + 1; bump(); } print "$g\n";');
    is ops( $r->{'package-scalar-loop-value'} ), ['Phi'], 'the value Phi a callee cannot reach';
};

subtest 'phi-arity: a Phi must pair with its Region\'s ways in' => sub {
    my $r = rules( graph(
        nd( 0, 'Start', [] ), nd( 1, 'Constant', [] ),
        nd( 2, 'If', [ 0, 1 ], ctl => 0 ), nd( 3, 'Proj', [2], index => 0 ), nd( 4, 'Proj', [2], index => 1 ),
        nd( 5, 'Region', [ 3, 4 ] ), nd( 6, 'Phi', [ 1, 1, 1 ], region => 5 ),
        nd( 7, 'Phi', [1], region => 99 ),
        nd( 8, 'Return', [6], ctl => 5 ),
    ) );
    is [ map { $_->{node} } $r->{'phi-arity'}->@* ], [6], 'three inputs for two ways in';
    is [ map { $_->{node} } $r->{'phi-no-region'}->@* ], [7], 'a Phi of no Region';
};

subtest 'write-off-chain and memory-input-not-version' => sub {
    my $r = rules( graph(
        nd( 0, 'Start', [] ), nd( 1, 'Constant', [] ), nd( 2, 'MemStart', [] ),
        nd( 3, 'EntryDef', [], sigil => '$', symbol => 'g', package => 'main' ),
        # pinned to a Proj nothing leads to
        nd( 4, 'Proj', [9], index => 0 ),
        nd( 5, 'EntryWrite', [ 3, 1, 2 ], ctl => 4 ),
        # reads memory "at" a constant
        nd( 6, 'EntryDef', [1], sigil => '$', symbol => 'g', package => 'main' ),
        nd( 7, 'Print', [6], ctl => 0 ),
        nd( 8, 'Return', [1], ctl => 7 ),
    ) );
    is [ map { $_->{node} } $r->{'write-off-chain'}->@* ], [5], 'pinned, but not reachable from Start';
    is [ map { $_->{node} } $r->{'memory-input-not-version'}->@* ], [6], 'a memory input that is no version';
};

subtest 'memory-order-disagrees: the two orderings name different versions' => sub {
    my $r = rules( graph(
        nd( 0, 'Start', [] ), nd( 1, 'Constant', [] ), nd( 2, 'MemStart', [] ),
        nd( 3, 'EntryDef', [], sigil => '$', symbol => 'g', package => 'main' ),
        nd( 4, 'EntryWrite', [ 3, 1, 2 ], ctl => 0 ),
        # follows 4 by control, but says it follows MemStart
        nd( 5, 'EntryWrite', [ 3, 1, 2 ], ctl => 4 ),
        nd( 6, 'Return', [1], ctl => 5 ),
    ) );
    is [ map { $_->{node} } $r->{'memory-order-disagrees'}->@* ], [5], 'control says 4, the input says MemStart';
};

subtest 'return-off-chain: a graph whose Return is not reached from Start' => sub {
    my $r = rules( graph( nd( 0, 'Start', [] ), nd( 1, 'Constant', [] ), nd( 2, 'Return', [1] ) ) );
    is [ map { $_->{node} } $r->{'return-off-chain'}->@* ], [2], 'an unpinned Return';
};

sub explain_v ($v) { join "\n", map { "$_->{graph}#$_->{node} $_->{op} $_->{rule}: $_->{detail}" } @$v }

done_testing;
