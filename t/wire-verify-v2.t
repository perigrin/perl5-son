# ABOUTME: SoN::Verify's wire v2 rules (the plan's section 8.1, V1 to V9): one hand-built
# ABOUTME: graph that breaks each, clean programs B::SoN made, and review focus 1 and 2.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

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
sub rules ($w) {
    $w = wire($w) unless ref $w;
    my %by;
    push $by{ $_->{rule} }->@*, $_ for SoN::Verify::verify($w)->{violations}->@*;
    return \%by;
}
sub v2 (@nodes) {
    return { version => 2, profile => ['mem'],
        methods => { g => { returns => [ $nodes[-1]{id} ], nodes => \@nodes } } };
}
# nd(id, op, [inputs], ctl => C, mem => M, out => 1, field => value ...)
sub nd ( $id, $op, $in, %rest ) {
    my %n = ( id => $id, op => $op, inputs => $in );
    $n{control_in} = delete $rest{ctl} if exists $rest{ctl};
    $n{mem_in}     = delete $rest{mem} if exists $rest{mem};
    $n{mem_out}    = JSON::PP::true if delete $rest{out};
    $n{fields}     = {%rest} if %rest;
    return \%n;
}
sub rule_names ($r) { [ sort keys %$r ] }

# A store and a read, all well formed: the base the bad graphs vary.
sub good (@extra) {
    return v2(
        nd( 0, 'Start', [] ), nd( 1, 'MemStart', [] ), nd( 2, 'Constant', [] ),
        nd( 3, 'EntryDef', [], package => 'main', sigil => '$', symbol => 'g' ),
        nd( 4, 'EntryWrite', [ 3, 2 ], ctl => 0, mem => 1, out => 1 ),
        nd( 5, 'EntryDef', [], mem => 4, package => 'main', sigil => '$', symbol => 'g' ),
        @extra,
        nd( 9, 'Return', [5], ctl => 4, mem => 4 ),
    );
}

subtest 'a well-formed v2 graph has no violation' => sub {
    is rules( good() ), {}, 'none';
};

subtest 'V1 mem-in-not-version' => sub {
    my $g = good();
    $g->{methods}{g}{nodes}[5]{mem_in} = 2;    # a Constant
    is rule_names( rules($g) ), ['mem-in-not-version'], 'a mem_in naming a Constant';
    my $p = v2(
        nd( 0, 'Start', [] ), nd( 1, 'MemStart', [] ), nd( 2, 'Constant', [] ),
        nd( 3, 'If', [ 0, 2 ], ctl => 0 ), nd( 4, 'Proj', [3], index => 0 ), nd( 5, 'Proj', [3], index => 1 ),
        nd( 6, 'Region', [ 4, 5 ] ),
        nd( 7, 'Phi', [ 1, 2 ], region => 6, memory => JSON::PP::true ),
        nd( 9, 'Return', [2], ctl => 6, mem => 7 ),
    );
    is rule_names( rules($p) ), ['mem-in-not-version'], 'a memory Phi over a Constant';
};

subtest 'V2 version-off-chain' => sub {
    my $g = good();
    delete $g->{methods}{g}{nodes}[4]{control_in};
    $g->{methods}{g}{nodes}[6]{control_in} = 0;
    ok scalar( grep { $_ eq 'version-off-chain' } rule_names( rules($g) )->@* ), 'a version with no control_in';
    my $r = good();
    delete $r->{methods}{g}{nodes}[6]{mem_in};
    is rule_names( rules($r) ), [ 'version-off-chain', 'write-unreachable' ],
        'a Return with no mem_in (and so no root reaches the store)';
    my $c = good( nd( 6, 'Call', [], ctl => 4, dispatch_kind => 'direct', name => 'f' ) );
    $c->{methods}{g}{nodes}[7]{control_in} = 6;
    is rule_names( rules($c) ), ['version-off-chain'], 'a sub Call with no mem_in';
};

subtest 'V3 write-unreachable, and V4 roots' => sub {
    # The store is not what the Return names: a floating write.
    my $g = good();
    $g->{methods}{g}{nodes}[5]{mem_in} = 1;
    $g->{methods}{g}{nodes}[6]{mem_in} = 1;
    is rule_names( rules($g) ), [ 'memory-order-disagrees', 'write-unreachable' ],
        'a store the Return does not reach (and the Return says so against its control)';
    # An Unwind is a root: `$g = 1; die` (review focus 1).
    my $u = v2(
        nd( 0, 'Start', [] ), nd( 1, 'MemStart', [] ), nd( 2, 'Constant', [] ),
        nd( 3, 'EntryDef', [], package => 'main', sigil => '$', symbol => 'g' ),
        nd( 4, 'EntryWrite', [ 3, 2 ], ctl => 0, mem => 1, out => 1 ),
        nd( 9, 'Unwind', [ [2] ], ctl => 4, mem => 4 ),
    );
    is rules($u), {}, 'a write before an uncaught die is reached from the Unwind';
    # A pinned node nothing follows that is no root.
    my $s = good( nd( 10, 'Print', [2], ctl => 9 ) );
    is rule_names( rules($s) ), ['control-sink'], 'a pinned node with no successor that is no root';
};

subtest 'V5 memory-order-disagrees' => sub {
    my $g = good(
        nd( 6, 'EntryWrite', [ 3, 2 ], ctl => 4, mem => 1, out => 1 ),
    );
    $g->{methods}{g}{nodes}[7]{control_in} = 6;
    $g->{methods}{g}{nodes}[7]{mem_in}     = 6;
    is rule_names( rules($g) ), [ 'memory-order-disagrees', 'write-unreachable' ],
        'a store that follows MemStart in memory and the first store in control';
};

subtest 'V7 record' => sub {
    my $r = good(
        nd( 6, 'PadAccess', [], sigil => '$', symbol => 'x' ),
        nd( 7, 'Assign', [ 6, 2 ], record => JSON::PP::true, ctl => 4 ),
    );
    $r->{methods}{g}{nodes}[8]{control_in} = 7;
    is rule_names( rules($r) ), ['record'], 'a record on the control chain';
    my $s = good(
        nd( 6, 'Subscript', [ 3, 2 ], kind => 'hash' ),
        nd( 7, 'Assign', [ 6, 2 ], record => JSON::PP::true ),
    );
    is rule_names( rules($s) ), ['record'], 'a record whose target is an element: a store, no binding';
    my $f = good( nd( 6, 'Subscript', [ 3, 2 ], kind => 'hash' ), nd( 7, 'Assign', [ 6, 2 ] ) );
    is rule_names( rules($f) ), ['version-off-chain'], 'an Assign that is neither a record nor on the chains';
};

subtest 'V8 phi: a memory Phi used as a value, a value Phi as memory' => sub {
    my $p = v2(
        nd( 0, 'Start', [] ), nd( 1, 'MemStart', [] ), nd( 2, 'Constant', [] ),
        nd( 3, 'If', [ 0, 2 ], ctl => 0 ), nd( 4, 'Proj', [3], index => 0 ), nd( 5, 'Proj', [3], index => 1 ),
        nd( 6, 'Region', [ 4, 5 ] ),
        nd( 7, 'Phi', [ 1, 1 ], region => 6, memory => JSON::PP::true ),
        nd( 8, 'Phi', [ 2, 2 ], region => 6 ),
        nd( 9, 'Return', [7], ctl => 6, mem => 8 ),
    );
    is rule_names( rules($p) ), [ 'mem-in-not-version', 'memory-order-disagrees', 'phi:memory-as-value' ],
        'both (and the Return names other memory than its Region merges)';
};

subtest 'V9 control-fork holds on v2' => sub {
    my $g = good( nd( 6, 'Print', [2], ctl => 4 ) );
    $g->{methods}{g}{nodes}[6]{control_in} = 0;
    ok scalar( grep { $_ eq 'control-fork' } rule_names( rules($g) )->@* ), 'two successors of Start';
};

subtest 'programs B::SoN made' => sub {
    is rules('my @a = (1,2,3); $a[0] = 10; my $x = $a[0]; $a[1] = $x + 1; print "$a[0] $a[1]\n";'), {},
        'stores and reads in one chain';
    is rules('our $g; sub bump { $g += 10 } bump(); bump(); print "$g\n";'), {}, 'calls and a sub that stores';
    # REVIEW FOCUS 1: a write on a path that ends in a die outside any eval.
    my $r = rules('our $g = 0; sub f { $g = 1; die "x\n" } f();');
    is $r->{'write-unreachable'}, undef, '`$g = 1; die`: the Unwind is a root';
    # REVIEW FOCUS 2: a loop with no way out.
    my $l = rules('our $g = 0; while (1) { $g++ }');
    is $l->{'write-unreachable'}, undef, '`while (1) { $g++ }`: its writes reach the header memory Phi';
};

# A LOOP'S TEST CHAIN (a wire without the `loop` profile: the test's effects
# pinned to the Loop, its body hung off Proj 0 beside them): what the body
# follows is the test's last version, which control reaches only through the
# Loop. V5 asked the Loop's memory Phi and called 51 chalk graphs wrong.
subtest 'V5 at a loop whose test writes, without the loop profile' => sub {
    is rules('my @q = (1,2,3); my $s = 0; while (my $x = shift @q) { $s += $x; push @q, 10 if $x == 1 } print "$s\n";')
        ->{'memory-order-disagrees'}, undef, 'a body after `while (my $x = shift @q)` follows the shift';
    is rules('sub g { "<$_[0]>" } sub f { my @w = (1, 2); my $s = ""; while (my $n = shift @w) { $s .= g($n) } $s } print f(), "\n";')
        ->{'memory-order-disagrees'}, undef, 'a call in such a body (corpus 151)';
    # (falsified: the store's memory taken from before the test is still one)
    my $w = wire('my @q = (1,2); while (shift @q) { $q[0] = 5 } print "@q\n";');
    my ($st) = grep { $_->{op} eq 'Assign' } $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    my ($ms) = grep { $_->{op} eq 'MemStart' } $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    $st->{mem_in} = $ms->{id};
    ok rules($w)->{'memory-order-disagrees'}, 'a body store that skips the test still disagrees';
};

# WIRE V1 IS GONE (stage 6), and with it the rules only it needed
# (write-floating, effect-rides-value, fault-floating,
# package-scalar-loop-value): a wire of another version is refused by name,
# not checked by rules it does not obey.
subtest 'a wire that is not v2 is refused by name' => sub {
    my $v1 = good();
    $v1->{version} = 1;
    like dies { SoN::Verify::verify($v1) }, qr/\ASoN::Verify: wire version 1: the rules are wire v2's/, 'version 1';
    delete $v1->{version};
    like dies { SoN::Verify::verify($v1) }, qr/wire version none/, 'no version';
};

# V6, ITS CLASSES (moved from the v1 rules' test): a read of changeable state
# with no memory edge whose value is used.
subtest 'V6 read-unversioned:object-class: a ref() at no version (ef9)' => sub {
    my $r = rules( v2(
        nd( 0, 'Start', [] ), nd( 1, 'MemStart', [] ), nd( 2, 'HashLiteral', [] ), nd( 3, 'Constant', [] ),
        nd( 4, 'RefType', [2] ),
        nd( 5, 'Call', [ 2, 3 ], ctl => 0, mem => 1, out => 1, dispatch_kind => 'builtin', name => 'bless' ),
        nd( 6, 'Print', [4], ctl => 5 ),
        nd( 7, 'Return', [3], ctl => 6, mem => 5 ),
    ) );
    is [ map { $_->{op} } ( $r->{'read-unversioned:object-class'} // [] )->@* ], ['RefType'], 'a RefType with no mem_in';
    my $p = rules('my $o = {}; my $c = ref($o); bless $o, "K"; my $d = ref($o); print "$c $d\n";');
    is $p->{'read-unversioned:object-class'}, undef, 'the producer\'s ef9 reads each at its version';
};
subtest 'V6 read-unversioned:package-aggregate-literal: a flattened package array (nv1)' => sub {
    my $r = rules( v2(
        nd( 0, 'Start', [] ), nd( 1, 'MemStart', [] ), nd( 2, 'Constant', [] ),
        nd( 3, 'ArrayLiteral', [2], sigil => '@', symbol => '@main::st' ),
        nd( 4, 'ArrayLiteral', [ 3, 2 ], sigil => '@', symbol => 'c' ),
        nd( 5, 'Print', [4], ctl => 0 ),
        nd( 6, 'Return', [2], ctl => 5, mem => 1 ),
    ) );
    is [ map { $_->{op} } ( $r->{'read-unversioned:package-aggregate-literal'} // [] )->@* ], ['ArrayLiteral'],
        '@st read through its named literal';
    my $p = rules('our @st = (1); my @c = (@st, 2); @st = (); print "@c\n";');
    is [ grep { /\Aread-unversioned/ } keys %$p ], [], 'the producer reads @st at its version (stage 7)';
};
subtest 'V6: a read only a dead node takes is not used' => sub {
    my $r = rules( v2(
        nd( 0, 'Start', [] ), nd( 1, 'MemStart', [] ), nd( 2, 'Constant', [] ),
        nd( 3, 'EntryDef', [], package => 'main', sigil => '$', symbol => 'g' ),
        nd( 4, 'NumLt', [ 3, 2 ] ),
        nd( 5, 'Return', [2], ctl => 0, mem => 1 ),
    ) );
    is $r, {}, 'an EntryDef read by an unused NumLt: no violation';
    my $u = rules( v2(
        nd( 0, 'Start', [] ), nd( 1, 'MemStart', [] ), nd( 2, 'Constant', [] ),
        nd( 3, 'EntryDef', [], package => 'main', sigil => '$', symbol => 'g' ),
        nd( 4, 'NumLt', [ 3, 2 ] ),
        nd( 5, 'Return', [4], ctl => 0, mem => 1 ),
    ) );
    is [ keys %$u ], ['read-unversioned:package'], 'returned, it is';
    my $l = rules( v2(
        nd( 0, 'Start', [] ), nd( 1, 'MemStart', [] ), nd( 2, 'Constant', [] ),
        nd( 3, 'ArrayLiteral', [2], sigil => '@', symbol => '@main::INC' ),
        nd( 4, 'Region', [0] ),
        nd( 5, 'Phi', [3], region => 4 ),
        nd( 6, 'Return', [2], ctl => 4, mem => 1 ),
    ) );
    is $l, {}, 'a package literal only a dead Phi takes (DynaLoader::bootstrap): none';
};
subtest 'V6: an item of an alias list, a binding merged and read as a container, a parameter bind' => sub {
    is [ grep { /\Aread-unversioned/ } keys rules('our @g = (1, 2); my @n; push @n, 3; for my $x (@n, $g[0]) { print $x } print "\n";')->%* ], [],
        'foreach over a my array the sub writes, and an element';
    is [ grep { /\Aread-unversioned/ } keys rules('sub f { my @l; push @l, 1; if ($_[0]) { my @n = (2); @l = @n } return scalar(@l) . $l[0] } print f(1), f(0), "\n";')->%* ], [],
        'an array rebound in an arm, counted and indexed after the join';
    is [ grep { /\Aread-unversioned/ } keys rules('sub n { my ($c, %a) = @_; return bless {%a}, $c } print ref(n("K", a => 1)), "\n";')->%* ], [],
        'a slurpy hash bound from @_ and read whole';
    is [ grep { /\Aread-unversioned/ } keys rules('sub m1 { my ($r, $p) = @_; pos($r->$*) = $p; return $r->$* =~ /\Gb/gc ? pos($r->$*) : -1 } my $s = "abc"; print m1(\$s, 1), "\n";')->%* ], [],
        'pos() of a scalar through a reference, set: the variable, not its value (chalk Terminal::match_at)';
};
subtest 'V6: a list slice is of values, not a read of memory' => sub {
    my $r = rules( v2(
        nd( 0, 'Start', [] ), nd( 1, 'MemStart', [] ), nd( 2, 'Constant', [] ),
        nd( 3, 'Call', [], ctl => 0, mem => 1, out => 1, dispatch_kind => 'direct', name => 'main::f' ),
        nd( 4, 'Slice', [ 2, 3 ], index_count => 1 ),
        nd( 5, 'Print', [4], ctl => 3 ),
        nd( 6, 'Return', [2], ctl => 5, mem => 3 ),
    ) );
    is $r, {}, '(f())[0] has no violation';
};
subtest 'V8 phi-arity:eval-join: the eval join has one way in, two-input Phis' => sub {
    my $r = rules('my $x = 1; my $r = eval { $x = 2; die "a\n" if @ARGV; 5 }; print "$x $r $@\n";');
    is [ map { $_->{op} } ( $r->{'phi-arity:eval-join'} // [] )->@* ], ['Phi'], 'the value Phi of the eval (stage 8 gives it its edge)';
    is $r->{'phi-arity'}, undef, 'and it is not counted as an unknown mismatch';
};

done_testing;
