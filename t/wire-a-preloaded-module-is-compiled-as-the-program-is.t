# ABOUTME: A module the compiler loaded before B::SoN (Carp) is compiled again with
# ABOUTME: perl's peephole off, as the program is: its subs translate, none underflow.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub wire ($src) {
    my $f = "$dir/w." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    open my $e, '<', "$dir/err" or die $!; local $/; my $err = <$e>;
    return ( eval { JSON::PP->new->decode($j) }, $err );
}

my ( $d, $err ) = wire(q{use Carp; sub f { carp "w" } f(); print "ok\n";});
ok $d, 'translates';
unlike $err, qr/INTERNAL ERROR/, 'no internal error in a Carp sub';
# multideref, the peephole's fused element read, is what Carp's short_error_loc
# held: compiled again it is helem, and the sub translates.
ok exists $d->{methods}{'Carp::short_error_loc'}, 'Carp::short_error_loc translates';
ok !exists $d->{refused}{'Carp::trusts'}, 'Carp::trusts is not refused';
# A module that loads XS of its own is left as perl compiled it.
( $d, $err ) = wire(q{use Scalar::Util qw(blessed); print blessed(bless {}, "A"), "\n";});
ok $d, 'a module with XS of its own still translates';

done_testing;
