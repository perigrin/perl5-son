# ABOUTME: a match whose pattern is made at run time (`$s =~ /$p/i`) carries the match's
# ABOUTME: flags on the wire Match: no qr// constant carries them for a string.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub nodes_of ($src) {
    my $f = "$dir/m." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f;
    return decode_json($out)->{methods}{'main::__PROGRAM__'}{nodes};
}

# Without them chalk matched `/$p/i` case-sensitive (0 for perl's 1).
my ($m) = grep { $_->{op} eq 'Match' } nodes_of(q{my $p = "B"; my $x = "abc" =~ /$p/i ? 1 : 0; print "$x\n";})->@*;
is($m->{fields}{flags}, 'i', 'a /i match against a string pattern says i');
($m) = grep { $_->{op} eq 'Match' } nodes_of(q{my $p = "b"; my $x = "abc" =~ /$p/ ? 1 : 0; print "$x\n";})->@*;
is($m->{fields}{flags}, '', 'no flags: the empty string, not absent');

done_testing;
