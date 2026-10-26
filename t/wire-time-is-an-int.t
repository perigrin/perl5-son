# ABOUTME: time() reaches the wire stamped Int (whole seconds), and so does the
# ABOUTME: arithmetic over it -- untyped, everything it touched was TOP downstream.

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

my @n = nodes_of(q{my $p = 1 + time() * 0; print "$p\n";})->@*;
my ($t) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'time' } @n;
is $t->{stamp}, 'Int', 'time() is an Int';
my ($m) = grep { $_->{op} eq 'Multiply' } @n;
is $m->{stamp}, 'Int', 'time() * 0 is an Int';

done_testing;
