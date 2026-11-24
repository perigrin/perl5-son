# ABOUTME: A foreach iterator kept in memory (in an eval body) is its element: every write is a
# ABOUTME: store where it happens, nothing is written back, a die leaves it written (class G).
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use JSON::PP;

my $dir = tempdir(CLEANUP => 1);

sub translate ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    open my $e, '<', "$dir/err" or die $!;
    our $WIRE = $json =~ /\S/ ? decode_json($json) : undef;
    return join '', <$e>;
}
# write_back() -> an Assign on the last wire stores the iterator's slot ($x
# or $y) into an element: the pass-end write-back
sub write_back () {
    for my $g ( values( ( $main::WIRE // {} )->{methods}->%* ) ) {
        my %by = map { $_->{id} => $_ } ( $g->{nodes} // [] )->@*;
        return 1 if grep {
            my ( $t, $v ) = map { $by{$_} // {} } $_->{inputs}->@[ 0, 1 ];
            $_->{op} eq 'Assign' && ( $t->{op} // '' ) eq 'Subscript' && ( $v->{op} // '' ) eq 'PadAccess'
                && ( $v->{fields}{symbol} // '' ) =~ /\A[xy]\z/
        } values %by;
    }
    return 0;
}

# The Exc edge out of the pass had no write-back (`1 2` for perl's `1! 2`):
# each was refused by name. The write is a store where it happens now.
for my $src (
    'my @a=(1,2); eval { for my $x (@a) { $x.="!"; die "x\n" } }; print "@a\n";',
    'my @a=(1,2); sub d { die "x\n" } eval { for my $x (@a) { $x.="!"; d() } }; print "@a\n";',
    'my @a=(1,2); eval { for my $x (@a) { $x.="!"; die "x\n" if $x eq "2!" } }; print "@a\n";',
    'my @a=(1,2); my $z=0; eval { for my $x (@a) { $x.="!"; my $q=1/$z; } }; print "@a\n";',
    'use feature q(try); no warnings; my @a=(1,2); try { for my $x (@a) { $x.="!"; die "x\n" } } catch ($e) { } print "@a\n";',
    'my $r=[1,2]; eval { for my $x (@$r) { $x.="!"; die "x\n" } }; print "@$r\n";',
    'my @a=(1,2); eval { for my $x (@a) { for my $y (@a) { $y.="!"; die "x\n" } } }; print "@a\n";',
    # (an increment of the iterator is a store where it stands too)
    'our @a=(1,2); eval { for my $x (@a) { $x++; $x++; die "x\n" if $x > 2 } }; print "@a\n";',
) {
    unlike translate($src), qr/GAP:/, "not refused: $src";
    ok !write_back(), "no write-back: $src";
}
# A list a call returns may be perl's aliases of what it read: refused by name.
like translate('my %h=(a=>1); eval { for my $v (values %h) { $v=5; die "x\n" } }; print "$h{a}\n";'),
    qr/GAP: a written foreach iterator over a list a call returns/, 'values: refused by name';

# Not refused: no way out of the pass, or nothing written.
for my $src (
    'my @a=(1,2); eval { for my $x (@a) { $x.="!" } }; print "@a\n";',
    'my @a=(1,2); eval { for my $x (@a) { die "x\n" if $x == 2 } }; print "@a\n";',
    'my @a=(1,2); for my $x (@a) { $x.="!" } print "@a\n";',
    # (an op= is stored where it stands, the element and the iterator both)
    'my @a=(1,2); eval { for my $x (@a) { $x*=5; die "x\n" if $x>5 } }; print "@a\n";',
    'my @a=(1,2); eval { for my $x (@a) { $x+=1; die "x\n" if $x == 2 } }; print "@a $@";',
) {
    unlike translate($src), qr/GAP:/, "not refused: $src";
}

done_testing;
