# ABOUTME: without strict refs, `$$n = 7` stores through a NAME -- any package scalar -- so a
# ABOUTME: package scalar read after it is read anew, at the store's memory version, not before.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
print $fh q{our $y; my $n = "y"; $$n = 7; print "$y\n";};
close $fh;
my $j = decode_json(scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null));
my %n;
my $walk; $walk = sub ($x) {
    if (ref $x eq 'HASH') { $n{ $x->{id} } = $x if defined $x->{op} && defined $x->{id} && !ref $x->{id}; $walk->($_) for values %$x }
    elsif (ref $x eq 'ARRAY') { $walk->($_) for @$x }
};
$walk->($j->{methods}{'main::__PROGRAM__'});
my ($store) = grep { $_->{op} eq 'Assign' } values %n;
my ($read)  = grep { $_->{op} eq 'EntryDef' && ( $_->{fields}{symbol} // '' ) eq 'y' } values %n;
ok($store && $read, 'a store and a read of $y');
is($read->{inputs}[0], $store->{id}, 'the read is at the store\'s version');
done_testing;
