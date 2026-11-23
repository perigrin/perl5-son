# ABOUTME: What grep returns are aliases of the elements its block may write; the walk took each
# ABOUTME: value before the write. A list grep whose block writes $_ is refused by name.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub warnings_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return scalar qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>&1 >/dev/null);
}

# RE-AUDIT 2026-11-23, class F (probes/r e11, q14, q15, q16): `my @g = grep {
# $_ *= 2 } @a` gave @g 1 2 3 for perl's 2 4 6 -- the element read before the
# block wrote it.
my $GAP = qr/GAP: a grep whose block writes \$_, read as a list, is not yet lowered/;
my %refused = (
    'an op-assign'          => 'my @a=(1,2,3); my @g = grep { $_ *= 2 } @a; print "@a|@g\n";',
    'a decrement'           => 'my @a=(1,2,3); my @b = grep { $_-- > 1 } @a; print "@a|@b\n";',
    'into a list assign'    => 'my @a=(1,2,3); my ($f) = grep { $_++ } @a; print "$f @a\n";',
    'under a map'           => 'my @a=(1,2,3); my @g = map { $_ } grep { $_-- > 1 } @a; print "@g\n";',
    'a substitution'        => 'my @a=("a1","b2"); my @g = grep { s/\d// } @a; print "@a|@g\n";',
    'a chop'                => 'my @a=("ab","cd"); my @g = grep { chop } @a; print "@a|@g\n";',
    'a callee writing $_[0]' => 'my @a=(1,2,3); sub w { $_[0]*=2; 1 } my @g = grep { w($_) } @a; print "@a|@g\n";',
    'a method writing $_[1]' => 'package O; sub new{bless{},shift} sub w { $_[1]*=2; 1 } package main; my $o=O->new; my @a=(1,2,3); my @g = grep { $o->w($_) } @a; print "@a|@g\n";',
    'an invocant written'  => 'package O; sub z { $_[0] = 0; 1 } package main; my @a=(bless({},"O")); my @g = grep { $_->z } @a; print scalar(@g), " $a[0]\n";',
);
like warnings_of($refused{$_}), $GAP, "refused: $_" for sort keys %refused;

unlike warnings_of('my @a=(1,2,3); my $n = grep { $_ *= 2 } @a; print "@a|$n\n";'),
    qr/GAP: a grep/, 'a grep counted is not refused';
unlike warnings_of('my @a=(1,2,3); my @g = grep { $_ > 1 } @a; print "@g\n";'),
    qr/GAP: a grep/, 'a grep that only reads $_ is not refused';

unlike warnings_of('use Scalar::Util qw(blessed); my @a=(bless({},"X"),1); my @g = grep { blessed($_) } @a; print scalar(@g), "\n";'),
    qr/GAP: a grep/, 'a grep passing $_ to a builtin that stores nothing (EffectTable) is not refused';

done_testing;
