# ABOUTME: The audit's hand-broken wires (2026-11-22, section 3): each good wire, broken one way,
# ABOUTME: is rejected by SoN::Verify; the unbroken wires verify clean. Run against fresh wires.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;
use SoN::AliasProof ();    # (loaded, so that the cases below can make it say "private")

# THE DEFECT: 12 hand-made breakages, and the verifier caught 0 of them. It
# trusted mem_out, derived `record`, had no rule for the eval's exceptional
# edge, and took a builtin with no EffectTable row for pure. Each case here
# finds its node by what it is, not by id, so a new producer cannot move it.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub wire ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    return JSON::PP->new->decode($json);
}
sub nodes ($w) { $w->{methods}{'main::__PROGRAM__'}{nodes} }
sub find ( $w, $test ) { my @x = grep { $test->($_) } nodes($w)->@*; return $x[0] }
sub fname ($x) { ( $x->{fields} // {} )->{name} // '' }

# off_chain($w, $x, @what): take $x off its chains -- each of 'control' and
# 'memory' -- and let what followed it follow what it followed.
sub off_chain ( $w, $x, @what ) {
    my %w = map { $_ => 1 } @what;
    for my $y ( nodes($w)->@* ) {
        if ( $w{memory} ) {
            $y->{mem_in} = $x->{mem_in} if ( $y->{mem_in} // -1 ) == $x->{id};
            $y->{inputs} = [ map { defined $_ && !ref && $_ == $x->{id} ? $x->{mem_in} : $_ } $y->{inputs}->@* ]
                if $y->{op} eq 'Phi' && $y->{fields}{memory};
        }
        $y->{control_in} = $x->{control_in} if $w{control} && ( $y->{control_in} // -1 ) == $x->{id};
    }
    delete $x->{mem_out} if $w{memory};
    delete $x->{mem_in}  if $w{memory} && $w{all};
    delete $x->{control_in} if $w{control};
}

my %src = (
    t1 => 'my $x = 1; my $r = \$x; ($x) = (7); print "$$r\n";',
    t2 => 'my @a=(1); push @a, 2; print "@a\n";',
    t4 => 'my $x = 1; my $r = \$x; $x = 2; my $y = $x; $$r = 3; print "$y $x\n";',
    t5 => 'our $g=1; sub f { die "x\n" } eval { local $g = 2; f() }; print "$g\n";',
    t6 => 'my $d = @ARGV; my $q = 1/$d; print "before\n"; print "$q\n";',
    t7 => 'our $g=1; sub f { local $g = 2; 1/$_[0] } eval { f(0) }; print "$g\n";',
    # (an Exc into a catch, of a die in a sort block that carries no eval_id)
    t8 => 'my @r = eval { sort { die "boom\n" if $a == 2; $a <=> $b } 3, 1, 2 }; print "[@r] $@";',
    # (a call at a loop's top, before the pass's local: the back edge passes
    # a restore of that local, so it is not live there -- probe p/lo22)
    t10 => 'our $g = 1; sub b { $g++ } for my $i (1..3) { b(); local $g = $g + 10; next if $i == 2; print "$g\n"; } print "$g\n";',
    t9 => 'eval \'package Other; sub g { "g$_[0]" } 1\' or die; sub f { return Other::g($_[0]) } print f(2), "\n";',
    # (aliases as places: a call whose callee stores the argument by name and
    # then reads @_)
    t11 => 'our $x=1; sub f { $x=2; $_[0] } print f($x), "\n";',
    # (an :lvalue sub called as a store's target: a call, run where it stands --
    # corpus 398, a Call on no chain)
    t12 => 'my $slot = 0; sub slot :lvalue { $slot } slot() = 42; print slot(), "\n";',
    # (design B, P1: a promoted argument -- the callee reads @_ and stores nothing)
    p1 => 'our $x=1; sub f { my $v = $_[0]; $x = 2; $v } print f($x), "\n";',
);
sub rejected ( $what, $w, $rule ) {
    my @v = SoN::Verify::verify($w)->{violations}->@*;
    ok( ( grep { $_->{rule} =~ $rule } @v ), "$what: rejected" )
        or diag join "\n", 'got: ' . ( join( '; ', map { "$_->{op}#$_->{node} $_->{rule}" } @v ) || 'CLEAN' );
}

for my $t ( sort keys %src ) {
    my @v = SoN::Verify::verify( wire( $src{$t} ) )->{violations}->@*;
    is [ map { "$_->{op}#$_->{node} $_->{rule} $_->{detail}" } @v ], [], "$t unbroken: clean";
}

{   my $w = wire( $src{t1} );
    my $a = find( $w, sub ($x) { $x->{op} eq 'Assign' && defined( $x->{fields}{targets} ) && $x->{mem_out} } );
    off_chain( $w, $a, qw(control memory all) );
    $a->{fields}{record} = JSON::PP::true;
    rejected( 'M1 a list assign to a memory `my` scalar, off both chains, called a record', $w, qr/\Arecord\z/ );
}
{   my $w = wire( $src{t4} );
    my @a = grep { $_->{op} eq 'Assign' && $_->{mem_out} } nodes($w)->@*;
    off_chain( $w, $a[1], 'memory' );
    $a[1]{mem_in} = $a[0]{id};
    rejected( 'M2 an Assign on the chain that is no version', $w, qr/\Aversion-off-chain\z/ );
}
{   my $w = wire( $src{t2} );
    off_chain( $w, find( $w, sub ($x) { $x->{op} eq 'Call' && fname($x) eq 'push' } ), qw(control memory all) );
    rejected( 'M3 a push on no chain', $w, qr/\Aeffect-floating\z/ );
}
{   my $w = wire( $src{t2} );
    my $p = find( $w, sub ($x) { $x->{op} eq 'Call' && fname($x) eq 'push' } );
    off_chain( $w, $p, 'memory' );
    $p->{mem_in} //= ( find( $w, sub ($x) { $x->{op} eq 'MemStart' } ) )->{id};
    rejected( 'M3b a push pinned, following memory, no version', $w, qr/\Aversion-off-chain\z/ );
}
{   my $w = wire( $src{t4} );
    my @r = grep { $_->{op} eq 'PadAccess' && ( $_->{fields}{symbol} // '' ) eq 'x' && defined $_->{mem_in} } nodes($w)->@*;
    delete $r[-1]{mem_in};
    rejected( 'M4 a read of a memory-kept `my $x` with no version', $w, qr/\Aread-unversioned/ );
}
{   my $w = wire( $src{t6} );
    off_chain( $w, find( $w, sub ($x) { $x->{op} eq 'Print' } ), 'control' );
    rejected( 'M6 a Print on no control chain', $w, qr/\Aeffect-floating\z/ );
}
{   my $w = wire( $src{t6} );
    off_chain( $w, find( $w, sub ($x) { $x->{op} eq 'Divide' } ), 'control' );
    rejected( 'M7 a division that may fault, floating', $w, qr/\Aeffect-floating\z/ );
}
{   # (the call's way out removed: its Exc, the work on it, the catch, and
    # the join's way in from there)
    my $w = wire( $src{t5} );
    my $exc = find( $w, sub ($x) { $x->{op} eq 'Exc' } );
    my %gone = ( $exc->{id} => 1 );
    for ( 1 .. 10 ) {
        for my $y ( nodes($w)->@* ) {
            $gone{ $y->{id} } = 1 if defined $y->{control_in} && $gone{ $y->{control_in} };
            $gone{ $y->{id} } = 1 if $y->{op} eq 'Region' && $y->{fields}{catch} && !grep { !$gone{$_} } $y->{inputs}->@*;
        }
    }
    my $join = find( $w, sub ($x) { $x->{op} eq 'Region' && defined $x->{fields}{eval_id} && !$x->{fields}{catch} } );
    my @keep = grep { !$gone{ $join->{inputs}[$_] } } 0 .. $join->{inputs}->$#*;
    for my $y ( nodes($w)->@* ) {
        $y->{inputs} = [ $y->{inputs}->@[@keep] ] if $y->{op} eq 'Phi' && $y->{fields}{region} == $join->{id};
    }
    $join->{inputs} = [ $join->{inputs}->@[@keep] ];
    $w->{methods}{'main::__PROGRAM__'}{nodes} = [ grep { !$gone{ $_->{id} } } nodes($w)->@* ];
    rejected( 'M8 a call in an eval with no Exc edge', $w, qr/\Aexc\z/ );
}
{   my $w = wire( $src{t5} );
    my $exc = find( $w, sub ($x) { $x->{op} eq 'Exc' } );
    my $r = find( $w, sub ($x) { $x->{op} eq 'EntryWrite' && ( $x->{control_in} // -1 ) == $exc->{id} } );
    off_chain( $w, $r, qw(control memory) );
    $w->{methods}{'main::__PROGRAM__'}{nodes} = [ grep { $_ != $r } nodes($w)->@* ];
    for my $y ( nodes($w)->@* ) { $y->{inputs} = [ map { defined $_ && !ref && $_ == $r->{id} ? $exc->{id} : $_ } $y->{inputs}->@* ] if $y->{op} eq 'Region' }
    rejected( 'M9 an Exc edge with its `local` restore removed', $w, qr/\Aexc\z/ );
}
{   my $w = wire( $src{t5} );
    my $c = find( $w, sub ($x) { $x->{op} eq 'Call' && fname($x) eq 'main::f' } );
    my $m = $c->{mem_in};
    off_chain( $w, $c, 'memory' );
    $c->{mem_in} = $m;
    rejected( 'M10 a sub call following memory, no version', $w, qr/\Aversion-off-chain\z/ );
}
{   my $w = wire( $src{t2} );
    my $j = find( $w, sub ($x) { $x->{op} eq 'Call' && fname($x) eq 'join' } );
    $j->{fields}{name} = 'getppid';
    delete $j->{mem_in};
    rejected( 'M11 a builtin with no EffectTable row, floating', $w, qr/\A(?:effect-floating|read-unversioned)/ );
}

# DESIGN B1 (docs/plans/2026-11-24-copy-and-local-unwind.md): outside an
# eval, something that may die under a live `local` leaves by an Exc, the
# restores, and an Unwind marked rethrow. Each broken the four ways V10 must
# see (t7's division in main::f).
sub fnodes ($w) { $w->{methods}{'main::f'}{nodes} }
sub rethrow_edge ($w) {
    my ($d) = grep { $_->{op} eq 'Divide' } fnodes($w)->@*;
    my ($x) = grep { $_->{op} eq 'Exc' && $_->{inputs}[0] == $d->{id} } fnodes($w)->@*;
    my @c;
    for ( my $at = $x->{id}; my ($s) = grep { ( $_->{control_in} // -1 ) == $at } fnodes($w)->@*; $at = $s->{id} ) { push @c, $s }
    return ( $d, $x, @c );
}
{   my $w = wire( $src{t7} );
    my ( $d, $x, @c ) = rethrow_edge($w);
    my %gone = map { ( $_->{id} => 1 ) } $x, @c;
    $w->{methods}{'main::f'}{nodes} = [ grep { !$gone{ $_->{id} } } fnodes($w)->@* ];
    rejected( 'M12 a division under a live local, outside an eval, with no way out', $w, qr/\Aexc\z/ );
}
{   my $w = wire( $src{t7} );
    my ( $d, $x, @c ) = rethrow_edge($w);
    my ($r) = grep { $_->{op} eq 'EntryWrite' } @c;
    $c[-1]{control_in} = $x->{id};
    $c[-1]{mem_in} = $r->{mem_in};
    $w->{methods}{'main::f'}{nodes} = [ grep { $_ != $r } fnodes($w)->@* ];
    rejected( 'M13 a rethrow edge with its `local` restore removed', $w, qr/\Aexc\z/ );
}
{   my $w = wire( $src{t7} );
    my ( $d, $x, @c ) = rethrow_edge($w);
    delete $c[-1]{fields}{rethrow};
    rejected( 'M14 a rethrow edge ending in a plain die', $w, qr/\Aexc\z/ );
}
{   my $w = wire( $src{t7} );
    my ( $d, $x, @c ) = rethrow_edge($w);
    $w->{methods}{'main::f'}{nodes} = [ grep { $_ != $c[-1] } fnodes($w)->@* ];
    rejected( 'M15 an Exc outside an eval whose edge leads nowhere', $w, qr/\A(?:exc|write-unreachable)\z/ );
}

{   my $w = wire( $src{t7} );
    my ( $d, $x, @c ) = rethrow_edge($w);
    $c[-1]{inputs} = [ $d->{id} ];
    my @v = SoN::Verify::verify($w)->{violations}->@*;
    ok( ( grep { $_->{rule} eq 'exc' && $_->{detail} =~ /a rethrow not of its own edge/ } @v ),
        'M16 a rethrow of what is not its edge\'s Exc: rejected' )
        or diag join '; ', map { "$_->{op}#$_->{node} $_->{rule} $_->{detail}" } @v;
}

# unplace($w, $node, $version): the place $node read as a value at $version --
# the alias carried as a value where it is not private (aliases-as-places).
sub unplace ( $node, $version ) {
    delete $node->{fields}{place};
    delete $node->{fields}{vivify};
    $node->{mem_in} = $version;
}
{   my $w = wire( $src{t11} );
    my $c = find( $w, sub ($x) { $x->{op} eq 'Call' && fname($x) eq 'main::f' } );
    my $a = find( $w, sub ($x) { $x->{id} == $c->{inputs}[0] } );
    unplace( $a, $c->{mem_in} );
    rejected( 'M17 an argument a callee stores by name before reading @_, passed as a value', $w, qr/\Aalias-not-private\z/ );
}
# A SUB CALL IS AN EFFECT where it stands, a store's target too (audit 3: corpus
# 398's lvalue call floated, and effect-floating asked only of builtins).
{   my $w = wire( $src{t12} );
    my $c = find( $w, sub ($x) { $x->{op} eq 'Call' && fname($x) eq 'main::slot' && defined $x->{control_in} } );
    off_chain( $w, $c, qw(control memory) );
    rejected( 'M18 a sub call taken off the control chain', $w, qr/\Aeffect-floating\z/ );
}
# promote($node): the place $node marked as SoN::Promote marks a value it proved
# private (design B, P1), read at the call's version.
sub promote ( $node, $version ) { unplace( $node, $version ); $node->{fields}{promoted} = JSON::PP::true }
{   my $w = wire( $src{p1} );
    my $c = find( $w, sub ($x) { $x->{op} eq 'Call' && fname($x) eq 'main::f' } );
    my $a = find( $w, sub ($x) { $x->{id} == $c->{inputs}[0] } );
    ok( $a->{fields}{promoted} && !$a->{fields}{place}, 'p1: the pass promoted the argument a callee only reads' );
}
for my $case (
    [ 'M19 a promoted argument a callee stores by name before reading @_', 'our $x=1; sub f { $x=2; $_[0] } print f($x), "\n";' ],
    [ 'M20 a promoted argument a callee stores by tr/// before reading @_', 'our $x="ab"; sub f { $x =~ tr/a/z/; $_[0] } print f($x), "\n";' ],
    [ 'M21 a promoted argument a callee stores through a reference', 'our $x=1; our $r=\\$x; sub f { $$r=2; $_[0] } print f($x), "\n";' ],
    [ 'M22 a promoted argument a callee stores through $_[0]', 'our $x=1; sub f { $_[0]=2; 0 } f($x); print "$x\n";' ],
    [ 'M23 a promoted argument a closure stores through its cell', 'my $x=1; my $f=sub { $x=2; $_[0] }; print $f->($x), "\n";' ],
    [ 'M24 a promoted element of a package array a callee stores', 'our @a=(1); sub f { $a[0]=2; $_[0] } print f($a[0]), "\n";' ],
) {
    my $w = wire( $case->[1] );
    my $c = find( $w, sub ($x) { $x->{op} eq 'Call' && ( fname($x) eq 'main::f' || fname($x) =~ /__ANON__/ ) } );
    my $a = find( $w, sub ($x) { $x->{id} == $c->{inputs}[0] } );
    ok( $a->{fields}{place}, "$case->[0]: the pass left it a place" );
    promote( $a, $c->{mem_in} );
    rejected( $case->[0], $w, qr/\Apromoted-not-private\z/ );
}
# A PROMOTED ARGUMENT READ WHERE PERL PUSHED IT -- before a later argument's
# call -- is checked over the chain between: clean where that call stores
# nothing it reads, rejected where it does.
{   my $w = wire( 'our $x=1; sub g { 1 } sub f { $_[0] } print f($x, g()), "\n";' );
    my $c = find( $w, sub ($x) { $x->{op} eq 'Call' && fname($x) eq 'main::f' } );
    my $a = find( $w, sub ($x) { $x->{id} == $c->{inputs}[0] } );
    ok( $a->{fields}{promoted} && ( $a->{mem_in} // -1 ) != $c->{mem_in}, 't14: promoted, read before the later argument\'s call' );
    is( [ map { $_->{rule} } SoN::Verify::verify($w)->{violations}->@* ], [], 't14: clean' );
}
{   my $w = wire( 'our $x=1; sub g { $x=2; 1 } sub f { $_[0] } print f($x, g()), "\n";' );
    my $c = find( $w, sub ($x) { $x->{op} eq 'Call' && fname($x) eq 'main::f' } );
    my $g = find( $w, sub ($x) { $x->{op} eq 'Call' && fname($x) eq 'main::g' } );
    my $a = find( $w, sub ($x) { $x->{id} == $c->{inputs}[0] } );
    promote( $a, $g->{mem_in} );
    rejected( 'M26 a promoted argument read before a later argument\'s call that stores it', $w, qr/\Apromoted-not-private\z/ );
}
# (fifth final audit, Q10: an index is a number that wraps, not a spelling:
# two are two elements only as two non-negative integer literals, or two
# string keys)
my @Q10 = (
    [ 'M38 a promoted element a callee stores at a negative constant index', 'my @a = (1,2); sub f { $a[-2] = 5; $_[0] } print f($a[0]), "\n";' ],
    [ 'M39 a promoted element at a negative index, its positive one stored', 'our @a = (1,2); sub f { $a[0] = 5; $_[0] } print f($a[-2]), "\n";' ],
    [ 'M40 a promoted element a callee stores at a fractional constant index', 'my @a = (1,2); sub f { $a[0.5] = 5; $_[0] } print f($a[0]), "\n";' ],
    [ 'M41 a promoted element a callee stores at a string constant index', 'our @a = (1,2); sub f { $a["01"] = 5; $_[0] } print f($a[1]), "\n";' ],
    [ 'M42 a promoted element a callee stores at a false constant index', 'my @a = (1,2); sub f { no warnings; $a[!1] = 5; $_[0] } print f($a[0]), "\n";' ],
    [ 'M43 a promoted element a callee stores at a `use constant` index', 'my @a = (1,2); use constant L => -1; sub f { $a[L] = 5; $_[0] } print f($a[1]), "\n";' ],
);
# V14 DOES NOT ASK THE PASS'S PROOF (audit 4, X5): SoN::AliasProof called a
# captured or referenced `my` private, and V14, asking the same module, passed
# all 16. Each wire here is the pass's, its argument promoted by hand, and
# checked with SoN::AliasProof answering "private" to every question: V14
# must still reject it by its own check.
for my $case (
    [ 'M27 a promoted argument a closure handed in stores', 'sub f { $_[1]->(); $_[0] } my $x = 1; print f($x, sub { $x = 5 }), "\n";' ],
    [ 'M28 a promoted `my` argument a callee stores through a file-level reference', 'my $x = 1; my $r = \\$x; sub f { $$r = 5; $_[0] } print f($x), "\n";' ],
    [ 'M29 a promoted `my` argument stored through a reference held in an array', 'my $x = 1; my @r = (\\$x); sub f { my $o = $_[0]; ${$_[1][0]} = 5; "$o$_[0]" } print f($x, \\@r), "\n";' ],
    [ 'M30 a promoted `my` argument stored through a reference held in a hash', 'my $x = 1; my %o = (r => \\$x); sub f { my $o = $_[0]; ${$_[1]{r}} = 5; "$o$_[0]" } print f($x, \\%o), "\n";' ],
    [ 'M31 a promoted element a callee stores through a reference to it', 'our @a = (1); my $r = \\$a[0]; sub f { $$r = 5; $_[0] } print f($a[0]), "\n";' ],
    [ 'M32 a promoted @_ element of the caller, its variable stored by name', 'our $x = 1; sub f { $x = 2; $_[0] } sub h { f($_[0]) } print h($x), "\n";', 'main::h' ],
    [ 'M33 a promoted element a callee stores at an index not known', 'our @a = (1, 2); sub f { $a[$_[1]] = 9; $_[0] } print f($a[0], 0), "\n";' ],
    [ 'M34 a promoted element whose array a callee assigns whole', 'our @a = (1); sub f { @a = (7); $_[0] } print f($a[0]), "\n";' ],
    [ 'M35 a promoted argument a callee stores by name after a `local` of another', 'our ($x, $y) = (1, 1); sub f { local $y = 3; $x = 2; $_[0] } print f($x), "\n";' ],
    @Q10,
) {
    my ( $what, $src, $g ) = @$case;
    my $w = wire($src);
    my ($c) = grep { $_->{op} eq 'Call' && fname($_) eq 'main::f' } $w->{methods}{ $g // 'main::__PROGRAM__' }{nodes}->@*;
    my ($a) = grep { $_->{id} == $c->{inputs}[0] } $w->{methods}{ $g // 'main::__PROGRAM__' }{nodes}->@*;
    ok( $a->{fields}{place}, "$what: the pass left it a place" );
    promote( $a, $c->{mem_in} );
    no warnings 'redefine';
    local *SoN::AliasProof::conflict       = sub { 0 };
    local *SoN::AliasProof::arg_private    = sub { undef };
    local *SoN::AliasProof::stored_between = sub { undef };
    local *SoN::AliasProof::args_escape    = sub { 0 };
    rejected( "$what (the pass's proof says private)", $w, qr/\Apromoted-not-private\z/ );
}
# THE PASS'S PROOF ALONE (Q10): the pass asks V14 too, so the place it leaves
# above is either's. Here V14 answers "private" to everything, the wire made
# with no promotion is promoted in this process, and SoN::AliasProof must
# still leave the argument a place.
for my $case (@Q10) {
    my ( $what, $src ) = @$case;
    local $ENV{SON_NO_PROMOTE} = 1;
    my $w = wire($src);
    delete local $ENV{SON_NO_PROMOTE};
    require SoN::Promote;
    require SoN::PromotedPrivate;
    no warnings 'redefine';
    local *SoN::PromotedPrivate::private_checker = sub { ( sub { undef }, sub { undef }, sub { }, sub { 1 } ) };
    SoN::Promote::promote($w);
    my $c = find( $w, sub ($x) { $x->{op} eq 'Call' && fname($x) eq 'main::f' } );
    my $a = find( $w, sub ($x) { $x->{id} == $c->{inputs}[0] } );
    ok( $a->{fields}{place} && !$a->{fields}{promoted}, "$what: SoN::AliasProof alone (V14 says private) leaves it a place" );
}
# V14 ANSWERS THE SAME WHATEVER IT WAS ASKED FIRST (combo2 ratchet: chalk's
# Earley::_complete, promoted by the pass, rejected by the verifier). Asked
# about a() first, the recursion b -> a took a() as QUIET while a() was being
# decided, and kept b() QUIET after a() was found to store $x: f2's argument,
# asked second, passed. Both calls here are promoted by hand; both must fail.
{   my $w = wire('our $x = 1; sub a { b() if $_[0]; $x = 2 } sub b { a(0) } sub f1 { a(1); $_[0] } sub f2 { b(); $_[0] } print f1($x), f2($x), "\n";');
    my @c = sort { $a->{id} <=> $b->{id} } grep { $_->{op} eq 'Call' && fname($_) =~ /\Amain::f[12]\z/ } nodes($w)->@*;
    is( scalar @c, 2, 'M36: two calls' );
    for my $c (@c) { my ($a) = grep { $_->{id} == $c->{inputs}[0] } nodes($w)->@*; promote( $a, $c->{mem_in} ) }
    no warnings 'redefine';
    local *SoN::AliasProof::conflict       = sub { 0 };
    local *SoN::AliasProof::arg_private    = sub { undef };
    local *SoN::AliasProof::stored_between = sub { undef };
    local *SoN::AliasProof::args_escape    = sub { 0 };
    my @v = grep { $_->{rule} eq 'promoted-not-private' } SoN::Verify::verify($w)->{violations}->@*;
    is( [ sort map { $_->{node} } @v ], [ sort map { $_->{id} } @c ], 'M36 a callee that reaches a store through a recursion asked second: both rejected' )
        or diag join "\n", map { "$_->{node} $_->{detail}" } @v;
}
# A `my` READ WHERE PERL PUSHED IT, BEFORE A LATER ARGUMENT'S CALL THAT IS
# HANDED IT (combo2 ratchet: chalk's `$self->_force($self->_chart_get(...))`,
# 18 graphs). The pass asked V14 of a wire whose g($s) it had already
# rewritten to a node V14 did not know (so: harmless), and V14 then took any
# input that names $s for a store (so: not). A call stores a `my` of the
# caller only through a place it is handed, where a callee may store @_.
{   my $w = wire('sub g { $_[0] } sub h { "$_[0]$_[1]" } sub k { my $s = shift; for my $i (1, 2) { $s .= $i } h($s, g($s)) } print k(1), "\n";');
    my $k = $w->{methods}{'main::k'}{nodes};
    my ($h) = grep { $_->{op} eq 'Call' && fname($_) eq 'main::h' } @$k;
    my ($a) = grep { $_->{id} == $h->{inputs}[0] } @$k;
    ok( $a->{fields}{promoted} && $a->{mem_in} != $h->{mem_in}, 't15: promoted, read where perl pushed it, before g($s)' );
    is( [ map { "$_->{graph}#$_->{node} $_->{rule}: $_->{detail}" } SoN::Verify::verify($w)->{violations}->@* ], [], 't15: clean' );
}
{   my $w = wire('sub g { $_[0] = 9 } sub h { "$_[0]$_[1]" } sub k { my $s = shift; for my $i (1, 2) { $s .= $i } h($s, g($s)) } print k(1), "\n";');
    my $k = $w->{methods}{'main::k'}{nodes};
    my ($h) = grep { $_->{op} eq 'Call' && fname($_) eq 'main::h' } @$k;
    my ($g) = grep { $_->{op} eq 'Call' && fname($_) eq 'main::g' } @$k;
    my ($a) = grep { $_->{id} == $h->{inputs}[0] } @$k;
    ok( !$a->{fields}{promoted} || $a->{mem_in} == $h->{mem_in}, 'M37: not read before g($s), which stores it through $_[0]' );
    promote( $a, $g->{mem_in} );
    no warnings 'redefine';
    local *SoN::AliasProof::conflict       = sub { 0 };
    local *SoN::AliasProof::arg_private    = sub { undef };
    local *SoN::AliasProof::stored_between = sub { undef };
    local *SoN::AliasProof::args_escape    = sub { 0 };
    rejected( 'M37 a promoted `my` read before a call it is handed as a place, which stores @_', $w, qr/\Apromoted-not-private\z/ );
}
# M44 (fifth final audit, Q10's vt59): A PROMOTED PARAMETER RECORD OF A SUB
# THAT STORES. The record binds each `my` to the argument as passed; an
# argument is an alias, and the sub's own store through a reference reached
# it before the `my` was read (`00` for perl's `10`). Each proof alone must
# refuse it: the pass with V14 saying private, V14 with the pass's proof
# saying private.
{   my $src = 'my $o = {l=>[1,2]}; sub f { my ($v, $s) = @_; $s->{l}[0] = 0; "$v$_[0]" } my @t; for my $x (@{$o->{l}}) { push @t, f($x, $o) } print "@t\n";';
    my $rec = sub ($w) { my ($r) = grep { $_->{op} eq 'Assign' && $_->{fields}{record} } $w->{methods}{'main::f'}{nodes}->@*; $r };
    {   local $ENV{SON_NO_PROMOTE} = 1;
        my $w = wire($src);
        delete local $ENV{SON_NO_PROMOTE};
        require SoN::Promote;
        require SoN::PromotedPrivate;
        no warnings 'redefine';
        local *SoN::PromotedPrivate::private_checker = sub { ( sub { undef }, sub { 1 }, sub { }, sub { 1 } ) };
        no warnings q{once};
        local %SoN::Promote::CALLED_UNKNOWN = ( q{main::f} => 0 );    # (B::SoN's: f is called by no code the wire cannot see)
        # (the arguments as P1 leaves them: values, no place -- what lets P2 run)
        my ($c) = grep { $_->{op} eq 'Call' && fname($_) eq 'main::f' } nodes($w)->@*;
        for my $a ( grep { my $i = $_->{id}; grep { $_ eq $i } $c->{inputs}->@* } nodes($w)->@* ) {
            promote( $a, $c->{mem_in} ) if $a->{fields}{place};
        }
        SoN::Promote::promote($w);
        ok( !$rec->($w)->{fields}{promoted}, 'M44: SoN::AliasProof alone (V14 says read-only) leaves the record of a sub that stores' );
    }
    my $w = wire($src);
    my $r = $rec->($w);
    unless ( $r->{fields}{promoted} ) {
        my $k = $r->{fields}{targets};
        my ($args) = grep { $_->{op} eq 'ArgsSource' } $w->{methods}{'main::f'}{nodes}->@*;
        $r->{inputs} = [ $r->{inputs}->@[ 0 .. $k - 1 ], $args->{id} ];
        $r->{fields}{promoted} = JSON::PP::true;
    }
    no warnings 'redefine';
    local *SoN::AliasProof::conflict       = sub { 0 };
    local *SoN::AliasProof::arg_private    = sub { undef };
    local *SoN::AliasProof::stored_between = sub { undef };
    local *SoN::AliasProof::args_escape    = sub { 0 };
    local *SoN::AliasProof::writes         = sub { {} };
    rejected( 'M44 a promoted parameter record of a sub that stores through a reference', $w, qr/\Apromoted-not-private\z/ );
}
# P2: a promoted parameter record, in a sub a call then hands a place.
{   my $w = wire( 'my $x=1; sub f { my ($p) = @_; $p } print f($x), "\n";' );
    my @f = $w->{methods}{'main::f'}{nodes}->@*;
    my ($rec) = grep { $_->{op} eq 'Assign' && $_->{fields}{record} } @f;
    ok( $rec && $rec->{fields}{promoted}, 't13: the pass promoted the parameter record of a sub no call hands a place' );
    my $c = find( $w, sub ($x) { $x->{op} eq 'Call' && fname($x) eq 'main::f' } );
    my $a = find( $w, sub ($x) { $x->{id} == $c->{inputs}[0] } );
    delete $a->{fields}{promoted}; delete $a->{mem_in}; delete $a->{mem_operand};
    $a->{fields}{place} = JSON::PP::true;
    rejected( 'M25 a promoted parameter record of a sub a call hands a place', $w, qr/\Apromoted-not-private\z/ );
}
done_testing;
