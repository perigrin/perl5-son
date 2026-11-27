# ABOUTME: A list assignment to elements or slices, in list context, is its targets as they are after
# ABOUTME: it (element reads at its version), not the Assign -- which a consumer read as its count.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $LIB = $ENV{SON_TEST_LIB} // 'lib';
my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub produce ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -I$LIB -MO=-q,SoN,json $f 2>$dir/err);
    my $err = do { local ( @ARGV, $/ ) = "$dir/err"; <> } // '';
    return ( ( $json =~ /\S/ ? JSON::PP->new->decode($json) : undef ), $err );
}

# (fourth final audit, X4: `my ($x,$y) = @a[0,1] = (8,9)` printed 2 for 89)
for my $src (
    'my @a = (1,2,3); my ($x,$y) = @a[1,2] = (8,9); print "$x$y@a\n";',
    'my %h; my ($x,$y) = @h{qw(a b)} = (8,9); print "$x$y\n";',
    'my @a = (1,2,3); my ($x,$y) = ($a[0],$a[1]) = (8,9); print "$x$y@a\n";',
    'my $r = [1,2,3]; my ($x,$y) = @$r[1,2] = (8,9); print "$x$y@$r\n";',
    'our @g = (1,2,3); my ($x,$y) = @g[1,2] = (8,9); print "$x$y@g\n";',
) {
    my ($w, $err) = produce($src);
    is $err =~ s/^\S+ syntax OK\n//mr, '', "translates: $src";
    my @n = $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    my %by = map { ( $_->{id} => $_ ) } @n;
    my @bad = grep { $_->{op} eq 'Assign' && grep { ( $by{$_}{op} // '' ) eq 'Assign' } ( $_->{inputs} // [] )->@* } @n;
    is scalar(@bad), 0, "no Assign is an item of another: $src";
}

# (indices that may be several: one read each is not perl's)
for my $src (
    'my @a=(1,2,3); sub f { (0,2) } my ($x,$y) = @a[f()] = (8,9); print "$x$y@a\n";',
    'my @a=(1,2,3); my ($x,$y) = @a[0..1] = (8,9); print "$x$y@a\n";',
) {
    my (undef, $err) = produce($src);
    like $err, qr/GAP: the value of a list assignment in list context, to a slice whose indices are a list/, "refused by name: $src";
}
done_testing;
