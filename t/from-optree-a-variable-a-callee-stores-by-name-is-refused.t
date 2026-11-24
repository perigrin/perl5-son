# ABOUTME: A variable passed to a sub that stores it by name and reads $_[N]: $_[N] is the
# ABOUTME: variable, the wire passes its value -- a GAP by name (final audit 2026-11-24, class C).
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

# Each printed the variable's value before the sub's store (1 for perl's 2).
my $NAME = qr/GAP: a variable passed to a sub that stores it by name/;
for my $src (
    'my $x=1; sub f { $x=2; $_[0] } print f($x), "\n";',
    'our $x=1; sub f { $x=2; $_[0] } print f($x), "\n";',
    'my $x=1; sub f { $x++; $_[0]+0 } print f($x),"\n";',
    'our $x=1; sub f { my $o=$_[0]; $x=2; "$o$_[0]" } print f($x),"\n";',
    'our @a=(1); sub f { $a[0]=2; $_[0] } print f($a[0]),"\n";',
    'my %h=(k=>1); sub f { $h{k}=2; $_[0] } print f($h{k}),"\n";',
    'our $x=1; sub g { $x=2 } sub f { g(); $_[0] } print f($x),"\n";',
    'our $x=1; sub f { $x=2; my ($v)=@_; $v } print f($x),"\n";',
    'our $x=1; sub f { $x=2; shift } print f($x),"\n";',
    'my $x=1; my $f=sub { $x=2; $_[0] }; print $f->($x),"\n";',
    'package C; our $x=1; sub m1 { $x=2; $_[1] } package main; print C->m1($C::x),"\n";',
    'my $o={n=>1}; sub f { $o->{n}=2; $_[0] } print f($o->{n}),"\n";',
    'my @a=(1); sub f { $a[0]=2; $_[0] } print f($a[0]),"\n";',
) {
    like translate($src), $NAME, "refused by name: $src";
}

# Not refused: the sub stores the variable but never reads its arguments, or
# reads them but stores nothing they name.
for my $src (
    'our $x=1; sub f { $x=2 } f($x); print "$x\n";',
    'my $x=1; sub f { $_[0] + 1 } print f($x), "\n";',
    'my $x=1; my $y=5; sub f { $y=2; $_[0] } print f($x), "\n";',
    'my @a=(1,2); sub f { $a[1]=9; $_[0] } print f($a[0]), "\n";',
    # (a store through $_[N] is the argument's copy-out, lowered)
    'my $x=1; sub inc { $_[0]++ } inc($x); print "$x\n";',
    'my @a=(1); sub inc { $_[0]++ } inc($a[0]); print "@a\n";',
    # (read before the store; a `local`; a reshape leaving the element; a
    # foreach over @_, whose alias reads each element where the body does)
    'our $x=1; sub f { my ($v)=@_; $x=2; $v } print f($x),"\n";',
    'our $x=1; sub f { local $x=2; $_[0] } print f($x),"\n";',
    'my @a=(1); sub f { push @a,2; $_[0] } print f($a[0]),"\n";',
    'our $x=1; sub f { $x=2; my $s=0; $s+=$_ for @_; $s } print f($x,$x),"\n";',
) {
    unlike translate($src), qr/GAP:/, "not refused: $src";
}

done_testing;
