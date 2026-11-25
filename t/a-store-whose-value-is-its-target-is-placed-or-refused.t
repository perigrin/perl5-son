# ABOUTME: A store whose value is its target (`$x = $y`, `$x .= "b"`, `++$x`) where a place is
# ABOUTME: needed -- a list assignment's target, an alias list's item -- is refused by name, not dropped.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use lib 'lib';
use JSON::PP;
use SoN::Verify;

# THE DEFECT (third final audit, N6, 13 probes): perl's `($x = $y) = 7`
# stores 7 into $x -- the assignment's value is $x itself. The walk took the
# value (2) and recorded a store of 7 into the Constant 2: well formed, no
# GAP, `2 2` for perl's `7 2`. `for ($x .= "b") { $_ .= "!" }` stored into
# the list's value. Each sink that takes a place now asks one question --
# is this item a store whose value is its target -- and the verifier's V13
# holds every store to a place.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub compile ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>&1);
}

my $list_gap  = qr/GAP: an assignment, op= or increment used as the target of a list assignment/;
my $alias_gap = qr/GAP: an assignment as an item of a foreach, map or grep list whose body may write its alias/;
for my $case (
    [ 'my ($x,$y)=(1,2); ($x = $y) = 7; print "$x $y\n";',                  $list_gap ],
    [ 'my $y=2; (my $z = $y) = 7; print "$z $y\n";',                         $list_gap ],
    [ 'my ($x,$y)=(1,2); (($x = $y)) = (7); print "$x $y\n";',               $list_gap ],
    [ 'my @a=(1); my $y=2; ($a[0] = $y) = 7; print "@a $y\n";',              $list_gap ],
    [ 'our ($x,$y)=(1,2); ($x = $y) = 7; print "$x $y\n";',                  $list_gap ],
    [ 'my ($x,$y)=(1,2); (($x, $y) = (5,6)) = (7); print "$x\n";',          $list_gap ],
    [ 'my $x="a"; $_ .= "!" for ($x .= "b"); print "$x\n";',                 $alias_gap ],
    [ 'my @a=("a"); for ($a[0] .= "b") { $_ .= "!" } print "@a\n";',         $alias_gap ],
    [ 'my $x="a"; for ($x x= 2) { $_ .= "!" } print "$x\n";',                $alias_gap ],
    [ 'my $x=1; for (++$x) { $_++ } print "$x\n";',                          $alias_gap ],
    [ 'my $x="a"; my @t = map { $_ .= "!" } ($x .= "b"); print "$x\n";',     $alias_gap ],
    [ 'my $x="a"; s/a/z/ for ($x .= "a"); print "$x\n";',                    $alias_gap ],
    [ 'my $x="a"; my @t = grep { s/a/z/ } ($x .= "a"); print "$x\n";',       $alias_gap ],
) {
    like compile( $case->[0] ), $case->[1], "refused: $case->[0]";
}

# (a value that is no store, or a body that stores no alias: lowered as before)
for my $src (
    'my ($x,$y)=(1,2); ($x, $y) = ($y, $x); print "$x $y\n";',
    'my ($x,$y); (undef, $y) = (1, 2); print "$y\n";',
    'my $x="a"; for my $v ($x . "b") { print $v } print "\n";',
    'my $x=1; for (++$x) { print $_ } print "\n";',
    'my $x="a"; for my $v ($x .= "b") { print $v } print "$x\n";',
    'my $x=1; my @l = map { $_ * 2 } ($x += 1); print "@l\n";',
    # (a list assignment into one array, as an item, is that array: POSIX's
    # `s/^(?=\w+_h$)/:/ for my @list = @_`, which the walk aliases)
    'sub f { s/^/:/ for my @list = @_; "@list" } print f("x", "y"), "\n";',
) {
    unlike compile($src), qr/GAP/, "not refused: $src";
}

# V13: a store into a value is a violation of the wire.
{
    my $w = decode_json( compile('my ($x,$y)=(1,2); ($x, $y) = (3, 4); print "$x $y\n";') =~ s/\A[^{]*//r );
    my ($a) = grep { $_->{op} eq 'Assign' && ( $_->{fields}{targets} // 0 ) == 2 } $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    ok $a, 'a two-target list assign';
    my ($c) = grep { $_->{op} eq 'Constant' && ( $_->{fields}{const_type} // '' ) ne 'undef' } $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    $a->{inputs}[0] = $c->{id};
    ok( ( grep { $_->{rule} eq 'store-into-value' } SoN::Verify::verify($w)->{violations}->@* ), 'a store into a Constant is store-into-value' );
}

done_testing;
