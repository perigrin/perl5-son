# ABOUTME: a package scalar some sub writes is read through memory, not forwarded --
# ABOUTME: whichever package that sub is in (a tie class's methods log to main's).
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
print $fh q{package P; sub f { $main::L .= "x"; 1 } package main; print "a$main::L "; P::f(); print "b$main::L\n";};
close $fh;
my $j = decode_json(scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null));
my %n;
my $walk; $walk = sub ($x) {
    if (ref $x eq 'HASH') { $n{ $x->{id} } = $x if defined $x->{op} && defined $x->{id} && !ref $x->{id}; $walk->($_) for values %$x }
    elsif (ref $x eq 'ARRAY') { $walk->($_) for @$x }
};
$walk->($j->{methods}{'main::__PROGRAM__'});
is(scalar( grep { $_->{op} eq 'EntryDef' && ( $_->{fields}{symbol} // '' ) eq 'L' } values %n ), 2,
    'two reads of $main::L, either side of a call into the package that writes it');
done_testing;
