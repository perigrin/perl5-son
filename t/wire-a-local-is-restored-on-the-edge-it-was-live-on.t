# ABOUTME: Wire v2's `eval` profile: each thing in an eval that may die has its own way out, and
# ABOUTME: the restores on it are of the `local`s live there -- none before the local, one after.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# The plan's review focus 4: `eval { f(); local $g = 2; h() }`. f()'s edge
# carries no restore (the local is not made yet); h()'s carries one.
my $dir = tempdir( CLEANUP => 1 );
my $f = "$dir/p.pl";
open my $o, '>', $f or die $!;
print $o q{our $g = 1; sub f { 0 } sub h { die "h\n" } eval { f(); local $g = 2; h() }; print "$g $@";};
close $o;
my $w = JSON::PP->new->utf8->decode( scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err) );
my @n  = $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
my %by = map { $_->{id} => $_ } @n;
my %call = map { ( $_->{fields}{name} =~ s/^main:://r ) => $_ } grep { $_->{op} eq 'Call' && ( $_->{fields}{dispatch_kind} // '' ) ne 'builtin' } @n;
ok $call{f} && $call{h}, 'the two calls' or return;
my %exc = map { my $c = $_; ( $c => ( grep { $_->{op} eq 'Exc' && $_->{inputs}[0] == $call{$c}{id} } @n )[0] ) } qw(f h);
ok $exc{f} && $exc{h}, 'each call has its Exc' or return;

# on_edge($exc) -> the nodes that stand on it, in order, to the catch
sub on_edge ($x) {
    my @s;
    for ( my $at = $x; ; ) {
        my ($next) = grep { ( $_->{control_in} // -1 ) == $at->{id} } @n or last;
        push @s, $next;
        $at = $next;
    }
    return @s;
}
is [ on_edge( $exc{f} ) ], [], 'f()\'s edge: nothing stands on it (the local is not made yet)';
my @h = on_edge( $exc{h} );
is scalar @h, 1, 'h()\'s edge: one restore';
is $h[0]{op}, 'EntryWrite', '... a store';
is( ( $by{ $h[0]{inputs}[0] }{fields} // {} )->{symbol}, 'g', '... of $g' );
is $h[0]{mem_in}, $call{h}{id}, '... after the call (its memory: what the callee wrote is in it)';

my ($catch) = grep { $_->{op} eq 'Region' && ( $_->{fields} // {} )->{catch} } @n;
is [ sort { $a <=> $b } $catch->{inputs}->@* ], [ sort { $a <=> $b } $exc{f}{id}, $h[0]{id} ], 'the catch Region merges the two edges';
my @phi = grep { $_->{op} eq 'Phi' && ( $_->{fields}{region} // -1 ) == $catch->{id} } @n;
my ($mem) = grep { $_->{fields}{memory} } @phi;
my ($val) = grep { !$_->{fields}{memory} } @phi;
ok $mem, 'a memory Phi there';
ok $val, 'and a Phi of the exceptions in flight';
is [ sort { $a <=> $b } $val->{inputs}->@* ], [ sort { $a <=> $b } $exc{f}{id}, $exc{h}{id} ], '... the two Excs';
done_testing;
