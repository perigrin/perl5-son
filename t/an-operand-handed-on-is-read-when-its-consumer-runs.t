# ABOUTME: An SV operand perl pushes and an op hands on as it is -- a slice index, substr's offset,
# ABOUTME: scalar(), do {}, || // && -- is read when its consumer runs; a list of aliases is refused.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub produce ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err);
    my $err = do { local ( @ARGV, $/ ) = "$dir/err"; <> } // '';
    return ( ( $json =~ /\S/ ? JSON::PP->new->decode($json) : undef ), $err =~ s/^\S+ syntax OK\n//mr );
}

# (fourth final audit, X7: `$x` read at the version before c(), which stores
# it -- `@a[$x, c()]` gave `20 20` for perl's `60 20`)
my $C = 'our $x = 1; sub c { $x = 3; 2 } ';
for my $src (
    'our $x = 1; sub c { $x = 5; 1 } my @a = (10,20,30,40,50,60); my @l = @a[$x, c()]; print "@l\n";',
    'our $x = "b"; sub c { $x = "a"; "c" } my %h = (a=>1,b=>2,c=>3); my @l = @h{$x, c()}; print "@l\n";',
    $C . 'my $s = substr("abcdef", $x, c()); print "$s\n";',
    $C . 'my $s = do { $x } + c(); print "$s\n";',
    $C . 'my $s = scalar($x) . c(); print "$s\n";',
    $C . 'my $s = ($x || 0) . c(); print "$s\n";',
    $C . 'my @l = (do { $x }, c()); print "@l\n";',
    $C . 'my @l = (($x || 9), c()); print "@l\n";',
    $C . 'my @l = (($x // 9), c()); print "@l\n";',
) {
    my ( $w, $err ) = produce($src);
    is $err, '', "translates: $src";
    my @nodes = $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    my %call  = map { ( $_->{id} => 1 ) } grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'main::c' } @nodes;
    ok( ( grep { $_->{op} eq 'EntryDef' && ( $_->{fields}{symbol} // '' ) eq 'x' && $call{ $_->{mem_in} // '' } } @nodes ),
        "\$x is read again after the call: $src" );
}

# (a `do` of two statements is a leave, which copies: not read again)
{
    my ( $w ) = produce( $C . 'my @l = (do { 1; $x }, c()); print "@l\n";' );
    my @nodes = $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    my %call  = map { ( $_->{id} => 1 ) } grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'main::c' } @nodes;
    ok( !( grep { $_->{op} eq 'EntryDef' && ( $_->{fields}{symbol} // '' ) eq 'x' && $call{ $_->{mem_in} // '' } } @nodes ),
        'a do block of two statements is a copy' );
}
# (and map copies what its block yields: `1 2`, translated as it is)
is( ( produce( $C . 'my @l = ((map { $_ } $x), c()); print "@l\n";' ) )[1], '', 'a map of the SV is a copy' );

for my $case (
    [ $C . 'my @l = ((sort { $a <=> $b } $x, 0), c()); print "@l\n";', qr/GAP: a list perl aliases item by item/ ],
    [ $C . 'my @l = ((grep { 1 } $x), c()); print "@l\n";',            qr/GAP: a list perl aliases item by item/ ],
    [ $C . 'my @l = ((reverse $x), c()); print "@l\n";',               qr/GAP: a list perl aliases item by item/ ],
    [ $C . 'sub lv :lvalue { $x } my @l = (lv(), c()); print "@l\n";', qr/GAP: an :lvalue sub's value is the scalar it returns/ ],
    [ $C . 'my @l = (($x ? $x : 9), c()); print "@l\n";',              qr/GAP: an SV operand handed on by \?:/ ],
    # (audit 3, N5: `values` and a hash slice push the values themselves)
    [ 'my %h=(a=>1); my @b=(values %h, $h{a}=9); print "@b\n";',      qr/GAP: a list item perl aliases element by element/ ],
    [ 'my %h=(a=>1); my $s = join(",", values %h, $h{a}=9); print "$s\n";', qr/GAP: a list item perl aliases element by element/ ],
) {
    my ( undef, $err ) = produce( $case->[0] );
    like $err, $case->[1], "refused by name: $case->[0]";
}
done_testing;
