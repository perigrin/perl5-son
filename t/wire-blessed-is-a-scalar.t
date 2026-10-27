# ABOUTME: blessed() reaches the wire stamped Scalar -- a class name, or undef -- and
# ABOUTME: not Unknown, which made everything it touched TOP downstream.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub nodes_of ($src) {
    my $f = "$dir/t." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f;
    return decode_json($out)->{methods}{'main::__PROGRAM__'}{nodes};
}

my @n = nodes_of(q{use Scalar::Util qw(blessed); my $b = bless [], "P"; print blessed($b), "\n";})->@*;
my ($p) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'blessed' } @n;
is $p->{stamp}, 'Scalar', 'blessed() is a Scalar';

done_testing;
