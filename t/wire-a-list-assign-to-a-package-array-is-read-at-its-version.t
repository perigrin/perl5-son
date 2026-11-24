# ABOUTME: The value of `@a = LIST` for a package @a, where it is used (a sub's value), is @a read
# ABOUTME: at the version its store made -- not the literal the store wrote, which is no version.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use SoN::Verify;

my $dir = tempdir(CLEANUP => 1);

sub wire ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return JSON::PP->new->decode(scalar qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null));
}

# RE-AUDIT probe r/a12 (held by name in the ratchet at 216d190): `sub z { @a
# = () }` -- its Return read the package ArrayLiteral the EntryWrite stored, a
# read at no version (read-unversioned:package-aggregate-literal).
for my $src ('our @a=(1,2,3); sub z { @a=() } my $n=0; for (@a) { $n++; } z(); print "$n ".scalar(@a)."\n";',
             'our @a=(1,2,3); sub z { @a=(4,5) } my @r = z(); my $n = z(); print "@r $n\n";') {
    my $w = wire($src);
    is SoN::Verify::verify($w)->{violations}, [], "no violation: $src";
    my @n = $w->{methods}{'main::z'}{nodes}->@*;
    my %by = map { $_->{id} => $_ } @n;
    my ($ret) = grep { $_->{op} eq 'Return' } @n;
    my $v = $by{ $ret->{inputs}[0] };
    is [ $v->{op}, $v->{fields}{symbol}, defined $v->{mem_in} ? $by{ $v->{mem_in} }{op} : undef ],
        [ 'EntryDef', 'a', 'EntryWrite' ], 'the sub\'s value is @a at its store\'s version';
}

done_testing;
