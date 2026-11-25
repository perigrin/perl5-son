# ABOUTME: `substr($_[0], 0, 1) = "z"` (an lvalue substr of an element) reads the element where the call stands,
# ABOUTME: at a version, as a `my` string is read -- not with no version (audit 2, z/unverified/pa79).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub wire ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return JSON::PP->new->decode( scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>/dev/null) );
}
for my $src (
    'my $s="abc"; sub f { substr($_[0],0,1)="z" } f($s); print "$s\n";',
    'my @a=("abc"); substr($a[0],0,1)="z"; print "@a\n";',
) {
    my $w = wire($src);
    is [ map { "$_->{op}#$_->{node} $_->{rule}" } SoN::Verify::verify($w)->{violations}->@* ], [], "clean: $src";
    for my $g ( sort keys $w->{methods}->%* ) {
        my @n = $w->{methods}{$g}{nodes}->@*;
        my %by = map { $_->{id} => $_ } @n;
        for my $c ( grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'substr' && $_->{inputs}->@* == 4 } @n ) {
            my $t = $by{ $c->{inputs}[0] };
            $t = $by{ $t->{inputs}[0] } while $t->{op} eq 'Coerce';
            ok $t->{fields}{place} || defined $t->{mem_in}, "$g: the four-argument substr's string is a place or a read at a version";
        }
    }
}
done_testing;
