# ABOUTME: -e PATH (ftis) reaches the wire stamped Scalar -- 1, or undef -- and
# ABOUTME: not Unknown, which a defined() over it read as always defined.

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

my @n = nodes_of(q{my $f = $ENV{X} // "/no/such"; my $e = -e $f; print defined $e ? "d" : "u", "\n";})->@*;
my ($p) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'ftis' } @n;
is $p->{stamp}, 'Scalar', '-e is a Scalar';

done_testing;
