# ABOUTME: `$o->A::hi` (perl's method_redir) is a method Call named "A::hi", and
# ABOUTME: `$o->A::SUPER::hi` (method_redir_super) one named "A::SUPER::hi" -- not `unknown`.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
print $fh q{package A; sub new { bless {}, shift } sub hi { 1 } package main; my $o = A->new; $o->A::hi; $o->A::SUPER::hi;};
close $fh;
my $json = qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null);
my %name;
my $walk; $walk = sub ($x) {
    if (ref $x eq 'HASH') { $name{ $x->{fields}{name} } = $x->{fields}{dispatch_kind} if ( $x->{op} // '' ) eq 'Call'; $walk->($_) for values %$x }
    elsif (ref $x eq 'ARRAY') { $walk->($_) for @$x }
};
$walk->(decode_json($json));
is($name{'A::hi'}, 'method', '$o->A::hi is a method call named A::hi');
is($name{'A::SUPER::hi'}, 'method', '$o->A::SUPER::hi is one named A::SUPER::hi');
ok(!exists $name{unknown}, 'no call is unknown');
done_testing;
