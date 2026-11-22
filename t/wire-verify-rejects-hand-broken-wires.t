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

done_testing;
