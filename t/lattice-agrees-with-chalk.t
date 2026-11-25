# ABOUTME: B::SoN's type lattice (SoN::IR::Stamp) and chalk's (Chalk::Grammar::Perl::TypeLibrary)
# ABOUTME: are one lattice: same names, same parents, same subtype/join/meet on every pair.
use v5.42.0;
use Test2::V0;

use SoN::IR::Stamp;

# WHY. The two repos keep the lattice twice, by design (B::SoN must not load
# Chalk). Until they read one file (docs/plans/2026-11-25-one-lattice-one-table.md)
# this is what keeps the copies identical: a type added on one side fails here
# until the other has it. chalk's t/bootstrap/lattice-agrees-with-b-son.t is
# the same check from the other side.
my $chalk = $ENV{SON_CHALK} // "$ENV{HOME}/dev/chalk";
skip_all "chalk not found at $chalk (set SON_CHALK)"
    unless -f "$chalk/lib/Chalk/Grammar/Perl/TypeLibrary.pm";
push @INC, "$chalk/lib";    # after ours: only Chalk:: modules come from there
require Chalk::Grammar::Perl::TypeLibrary;
my $C = 'Chalk::Grammar::Perl::TypeLibrary';

my $son = SoN::IR::Stamp::lattice_parents();
my $chk = $C->can('lattice_parents')->();

is( [ sort keys $son->%* ], [ sort keys $chk->%* ], 'the same type names' );
is( $son, $chk, 'the same parent of every type' );

# Every name either side has, then Maybe[X] for each of them and Maybe of each
# valid Maybe: both sides must accept and refuse the same Maybes.
my %seen;
my @types = grep { !$seen{$_}++ } sort( keys $son->%*, keys $chk->%* );
my ( @valid, @refusal );
for my $t ( @types, map( "Maybe[$_]", @types ) ) {
    my $s = eval { SoN::IR::Stamp->new( type => $t ); 1 } ? 1 : 0;
    my $c = $C->can('is_lattice_type')->($t) ? 1 : 0;
    push @refusal, "$t: B::SoN=$s chalk=$c" if $s != $c;
    push @valid, $t if $s && $c;
}
for my $m ( grep { /\AMaybe\[/ } @valid ) {
    my $t = "Maybe[$m]";
    my $s = eval { SoN::IR::Stamp->new( type => $t ); 1 } ? 1 : 0;
    my $c = $C->can('is_lattice_type')->($t) ? 1 : 0;
    push @refusal, "$t: B::SoN=$s chalk=$c" if $s != $c;
}
is( \@refusal, [], 'the same names are lattice types, Maybe[...] included' );
ok( ( grep { /\AMaybe\[/ } @valid ) >= 10, 'the pair set holds a Maybe of every scalar type' );

my @diff;
for my $a (@valid) {
    my $sa = SoN::IR::Stamp->new( type => $a );
    for my $b (@valid) {
        my $sb = SoN::IR::Stamp->new( type => $b );
        my @r = (
            [ is_subtype => ( $sa->is_subtype_of($sb) ? 1 : 0 ),
                            ( $C->can('is_subtype')->( $a, $b ) ? 1 : 0 ) ],
            [ join => SoN::IR::Stamp::join( $sa, $sb )->type, $C->can('join_types')->( $a, $b ) ],
            [ meet => SoN::IR::Stamp::meet( $sa, $sb )->type, $C->can('meet_types')->( $a, $b ) ],
        );
        push @diff, map { "$_->[0]($a, $b): B::SoN=$_->[1] chalk=$_->[2]" }
            grep { $_->[1] ne $_->[2] } @r;
    }
}
diag "  $_" for @diff;
is( scalar @diff, 0, 'is_subtype, join and meet agree on all ' . @valid**2 . ' ordered pairs' );

done_testing;
