# ABOUTME: A foreach iterator set, in its pass, to another variable's loop Phi (a swap) is stored into
# ABOUTME: its element where it stands; only the iterator's own loop Phi needs no store (audit 2, K8).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# THE DEFECT (second final audit, class K8): `for my $x (@a) { ($x, $y) =
# ($y, $x) }` left @a alone (perl `9 1 2`, lowered `1 2 2`). The alias write
# is stored at the write (store_at_write), which skipped any loop Phi as the
# iterator's own -- and $y's Phi is what $x was set to.

my $dir = tempdir( CLEANUP => 1 );
my $f = "$dir/p.pl";
open my $o, '>', $f or die $!;
print $o 'my @a=(1,2); my $y=9; for my $x (@a) { ($x,$y)=($y,$x) } print "@a $y\n";';
close $o;
my $w = JSON::PP->new->decode( scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>/dev/null) );
my @n = $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
my %by = map { $_->{id} => $_ } @n;
my @stores = grep {
    $_->{op} eq 'Assign' && defined $_->{control_in}
        && ( $by{ $_->{inputs}[0] }{op} // '' ) eq 'Subscript'
        && ( $by{ $by{ $_->{inputs}[0] }{inputs}[0] }{fields}{symbol} // '' ) eq 'a'
} @n;
is scalar(@stores), 1, 'the pass stores its element';
my $v = $by{ $stores[0]{inputs}[1] // '' } // {};
ok $v->{op} eq 'Phi' && !$v->{fields}{memory}, "what it stores is \$y's Phi";
done_testing;
