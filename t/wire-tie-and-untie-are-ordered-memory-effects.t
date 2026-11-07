# ABOUTME: tie and untie change what every later access of the container does, so
# ABOUTME: each is on the control chain and a memory version of its own.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
print $fh q{package TA; sub TIEARRAY { bless {}, shift } sub FETCHSIZE { 3 } sub STORE { 1 }
package main; my @a; my $o = tie @a, "TA"; $a[0] = 5; print scalar(@a), "\n"; untie @a; print scalar(@a), "\n";};
close $fh;
my $j = decode_json(scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null));
my %n;
my $walk; $walk = sub ($x) {
    if (ref $x eq 'HASH') { $n{ $x->{id} } = $x if defined $x->{op} && defined $x->{id} && !ref $x->{id}; $walk->($_) for values %$x }
    elsif (ref $x eq 'ARRAY') { $walk->($_) for @$x }
};
$walk->($j->{methods}{'main::__PROGRAM__'});
my ($tie)   = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'tie' } values %n;
my ($untie) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'untie' } values %n;
ok(defined $tie->{control_in}, 'tie is on the control chain');
my ($assign) = grep { $_->{op} eq 'Assign' } values %n;
# the store is after the tie: the tie is behind it on control
my ($c, %seen) = ($assign->{control_in});
$c = $n{$c}{control_in} while defined $c && !$seen{$c}++ && $c != $tie->{id};
is($c, $tie->{id}, 'the store comes after the tie');
my @counts = grep { $_->{op} eq 'Count' } values %n;
is(scalar @counts, 2, 'a count after untie is not the count before it');
ok(( grep { $_ == $untie->{id} } map { @{ $_->{inputs} } } @counts ), 'the later count reads the untie\'s memory');
done_testing;
