# ABOUTME: split's regex pattern carries its flags on the wire Constant, as a qr// does:
# ABOUTME: `split /x/i` without its i is a different separator.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub nodes_of ($src) {
    my $f = "$dir/s." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f;
    return decode_json($out)->{methods}{'main::__PROGRAM__'}{nodes};
}

# Without it chalk split "aXbxc" by "x" alone (2 fields for perl's 3).
my ($c) = grep { $_->{op} eq 'Constant' && ( $_->{fields}{const_type} // '' ) eq 'regex' }
    nodes_of(q{my @f = split /x/i, "aXbxc"; print scalar(@f), "\n";})->@*;
is($c->{fields}{flags}, 'i', 'split /x/i: the pattern says i');
($c) = grep { $_->{op} eq 'Constant' && ( $_->{fields}{const_type} // '' ) eq 'regex' }
    nodes_of(q{my @f = split /x/, "axb"; print scalar(@f), "\n";})->@*;
ok(!defined $c->{fields}{flags}, 'split /x/: no flags, as a qr// with none');

done_testing;
