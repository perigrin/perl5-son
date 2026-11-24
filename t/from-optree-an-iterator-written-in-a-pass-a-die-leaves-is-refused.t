# ABOUTME: A foreach iterator kept in memory (in an eval body) is written back at the pass's
# ABOUTME: end, which a die passes by: refused by name (final audit 2026-11-24, class G).
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub translate ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    open my $e, '<', "$dir/err" or die $!;
    return join '', <$e>;
}

# The Exc edge out of the pass had no write-back: `1 2` for perl's `1! 2`.
my $NAME = qr/GAP: a foreach iterator written in a pass a die may leave/;
for my $src (
    'my @a=(1,2); eval { for my $x (@a) { $x.="!"; die "x\n" } }; print "@a\n";',
    'my @a=(1,2); sub d { die "x\n" } eval { for my $x (@a) { $x.="!"; d() } }; print "@a\n";',
    'my @a=(1,2); eval { for my $x (@a) { $x.="!"; die "x\n" if $x eq "2!" } }; print "@a\n";',
    'my %h=(a=>1); eval { for my $v (values %h) { $v=5; die "x\n" } }; print "$h{a}\n";',
    'my @a=(1,2); my $z=0; eval { for my $x (@a) { $x.="!"; my $q=1/$z; } }; print "@a\n";',
    'use feature q(try); no warnings; my @a=(1,2); try { for my $x (@a) { $x.="!"; die "x\n" } } catch ($e) { } print "@a\n";',
    'my $r=[1,2]; eval { for my $x (@$r) { $x.="!"; die "x\n" } }; print "@$r\n";',
    'my @a=(1,2); eval { for my $x (@a) { for my $y (@a) { $y.="!"; die "x\n" } } }; print "@a\n";',
) {
    like translate($src), $NAME, "refused by name: $src";
}

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
