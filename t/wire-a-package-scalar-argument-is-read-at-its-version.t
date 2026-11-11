# ABOUTME: a package scalar passed to a sub is read where the call is, after what ran
# ABOUTME: before: perl marks an argument OPf_MOD (an alias), which is not a store target.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
print $fh 'our $G; sub w { my ($v) = @_; $G = $v; return 0 } sub r { my ($x) = @_; return $x }' . "\n"
        . 'w("a"); print r($G), "\n"; w("b"); print r($G), "\n";' . "\n";
close $fh;
my $w = decode_json( scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null) );
my @n  = @{ $w->{methods}{'main::__PROGRAM__'}{nodes} };
my %by = map { $_->{id} => $_ } @n;
my @args = map { $by{ $_->{inputs}[0] } } grep { $_->{op} eq 'Call' && $_->{fields}{name} eq 'main::r' } @n;
is scalar @args, 2, 'two calls of r';
isnt $args[0]{id}, $args[1]{id}, 'each reads $G for itself';
ok( ( @{ $args[0]{inputs} // [] } && @{ $args[1]{inputs} // [] } ), '... at a memory version (after the w that wrote it)' );
done_testing;
