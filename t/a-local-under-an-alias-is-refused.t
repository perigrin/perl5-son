# ABOUTME: A call that hands a sub a variable as a place, where that sub (or one it calls) localizes the
# ABOUTME: variable, is refused by name (audit 2, K2): perl's alias keeps the saved scalar, a place the name.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

# THE DEFECT (second final audit, class K2): `our $x=1; sub f { local $x=5;
# $_[0]=7; $x } print f($x), $x` printed 71 for perl's 57. `local` gives the
# NAME a new scalar; $_[0] still holds the old one. The wire models local as
# save, store, restore on one location, and a place is a pointer to that
# location, so the store lands in the new value. Which object a place names
# is a design question (a place that is the scalar, not the name); until it
# is answered, the call is refused.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub compile ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>&1);
}
my $gap = qr/GAP: a variable handed to a sub as its \$_\[N\] where that sub localizes it/;

for my $src (
    'our $x=1; sub f { local $x=5; $_[0]=7; $x } print f($x),$x,"\n";',
    'our $x=1; sub f { local $x=5; $_[0]++; $x } print f($x), $x, "\n";',
    'our %h=(k=>1); sub f { local $h{k}=5; $_[0] } print f($h{k}), "\n";',
    'our $x=1; sub f { local $x=5; g2($_[0]) } sub g2 { $_[0]=7; $x } print f($x), $x, "\n";',
    'our $x=1; sub f { my $r=\$_[0]; local $x=5; $$r=7; $x } print f($x),$x,"\n";',
    # (a code value: any sub the program has that localizes $x may be it)
    '$main::x=1; my %d=(f=>sub { local $main::x=5; $_[0]=7; $main::x }); print $d{f}->($main::x),$main::x,"\n";',
) {
    like compile($src), $gap, "refused: $src";
}

# (no place, or no local of what it names: lowered as before)
for my $src (
    'our $x=1; sub f { local $x=5; $_[0] } print f($x),$x,"\n";',
    'our $x=1; sub g { $_[0]=7 } sub f { local $x=5; g($x); $x } print f(),$x,"\n";',
    'our ($x,$y)=(1,2); sub f { local $y=5; $_[0]=7; $y } print f($x),$x,"\n";',
    # (a code value, where nothing the program has localizes what it is handed)
    'sub apply { my ($f,@l)=@_; map { $f->($_) } @l } my @r=apply(sub { $_[0]*2 }, 1,2); print "@r\n";',
    'sub k { $_[1]->(); $_[0] } sub w { my $v=1; my $s=sub { $v=9 }; k($v,$s) } print w(),"\n";',
) {
    unlike compile($src), qr/GAP/, "not refused: $src";
}

done_testing;
