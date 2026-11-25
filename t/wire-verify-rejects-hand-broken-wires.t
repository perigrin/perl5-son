# ABOUTME: The audit's hand-broken wires (2026-11-22, section 3): each good wire, broken one way,
# ABOUTME: is rejected by SoN::Verify; the unbroken wires verify clean. Run against fresh wires.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

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
done_testing;
