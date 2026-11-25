# ABOUTME: The value of `$g++` handed to a sub is a copy, never the variable's place, even where the
# ABOUTME: call's arguments are places (the callee stores $_[N]) -- audit 2, K6's neighbour.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# `our $g=1; sub f { $_[1]=9; "@_" } print f($g, $g++), " $g"` is `2 9 2`
# in perl: $_[1] is the temporary $g++ returned. The wire passed $g's place
# twice -- the old value was an EntryDef read, and _alias_place made every
# such read the variable -- so chalk printed `9 9 9`.

my $dir = tempdir( CLEANUP => 1 );
my $f = "$dir/p.pl";
open my $o, '>', $f or die $!;
print $o 'our $g=1; sub f { $_[1]=9; "@_" } print f($g, $g++), " $g\n";';
close $o;
my $w = JSON::PP->new->decode( scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>/dev/null) );
my @n = $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
my %by = map { $_->{id} => $_ } @n;
my ($call) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'main::f' } @n;
my ( $a0, $a1 ) = map { $by{$_} } $call->{inputs}->@[ 0, 1 ];
ok $a0->{fields}{place}, 'the first argument, $g, is its place';
ok !$a1->{fields}{place} && defined $a1->{mem_in}, 'the second, $g++, is the value read before the store';
done_testing;
