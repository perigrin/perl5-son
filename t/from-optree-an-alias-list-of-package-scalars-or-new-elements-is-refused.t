# ABOUTME: A foreach/map/grep list aliasing package scalars, or elements perl makes exist, has no
# ABOUTME: alias on the wire: a GAP by name, the shapes that match perl kept (final audit, class E).
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

# A package scalar in the list is an EntryDef with no version: read as 0, and
# a write to its alias lost (`0 0` for perl's `3 6`).
for my $src (
    'our ($x,$y)=(1,2); for ($x,$y) { $_*=3 } print "$x $y\n";',
    'our ($x,$y)=(1,2); for my $v ($x,$y) { $v*=3 } print "$x $y\n";',
    'our @a=(1,2); our $x=5; for (@a,$x) { $_*=2 } print "@a $x\n";',
    'our ($x,$y)=(1,2); $_*=3 for $x,$y; print "$x $y\n";',
    'our ($x,$y)=(1,2); map { $_*=3 } $x,$y; print "$x $y\n";',
    'our ($x,$y)=(1,2); my @g=grep { $_*=3 } $x,$y; print "$x $y\n";',
    'our ($x,$y)=(1,2); s/^/a/ for $x,$y; print "$x $y\n";',
    'our $x=1; for ($x) { $_++ } for ($x) { $_*=5 } print "$x\n";',
    'our ($x,$y)=(1,2); my $t=0; for ($x,$y) { $t+=$_ } print "$t\n";',
    'our $x=1; for my $v ($x) { $v .= "a" } print "$x\n";',
) {
    like translate($src), qr/GAP: a package scalar aliased by a foreach, map or grep/, "refused by name: $src";
}

# An element perl's alias makes exist (`for ($a[2]) {}` grows @a to 3).
for my $src (
    'my @a; for my $x ($a[2]) { } print scalar(@a),"\n";',
    'my %h; for my $x ($h{k}) { } print exists $h{k}?1:0,"\n";',
    'my @a; my @b=map { $_ } $a[2]; print scalar(@a),"\n";',
    'my @a; for (@a[0,1]) { } print scalar(@a),"\n";',
    'my @a; for my $x (@a[1..2]) { } print scalar(@a), "\n";',
    'my @a; sub noop {} noop(@a[0,1]); print scalar(@a),"\n";',
    'my %h; my @v=map { $_ } @h{qw(a)}; print scalar(keys %h),"\n";',
    'my %h; my @g=grep { 1 } $h{b}; print scalar(keys %h),"\n";',
    # (a literal shrunk since: its element is no longer known to be there)
    'my @a=(1,2,3); shift @a; shift @a; for my $x ($a[1]) { } print scalar(@a),"\n";',
) {
    like translate($src), qr/GAP: an element (?:or a slice )?perl's alias may make exist/, "refused by name: $src";
}

# Kept: what matches perl today.
for my $src (
    'our $x=1; for ($x) { $_=5 } print "$x\n";',
    'our $x=5; for my $y ($x) { $y=6 } print "$x\n";',
    'my %h=(a=>1); for my $v ($h{a},$h{b}) { $v//=5 } print join(",",map{"$_$h{$_}"}sort keys %h),"\n";',
    'my $o={a=>1,b=>2}; for ($o->{a},$o->{b}) { $_*=2 } print "$o->{a}$o->{b}\n";',
    'my %h; for my $v (@h{qw(a b)}) { $v=1 } print join("",sort keys %h),"\n";',
    'my @p=(1,2,3); my $n=""; for my $q (@p[1 .. $#p]) { $n .= $q } print "$n\n";',
    'sub g { $_[0] = 5 } my @n = (1, 2); g($_) for @n[1 .. 1]; print "@n\n";',
    'my @a=(1,2,3); for my $x ($a[1]) { print $x } print "\n";',
    'my @c = (4, 5, 6); my @m = map { $_ * 2 } @c[2, 0]; print "@m\n";',
) {
    unlike translate($src), qr/GAP:/, "not refused: $src";
}

done_testing;
