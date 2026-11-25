# ABOUTME: V10 counts a `local` live at a thing that may die in an eval only if it was not put back before
# ABOUTME: it: an inner block's local, closed, needs no restore on the eval's way out (audit 2, z/unverified/un75).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

# THE FALSE POSITIVE: `our $g=1; eval { { local $g=2; } die "x\n" }` -- perl
# prints 1, and so does chalk -- was rejected: "its way out does not put back
# the local of main:$:g". The local's block had closed before the die.

my $dir = tempdir( CLEANUP => 1 );
my $f = "$dir/p.pl";
open my $o, '>', $f or die $!;
print $o 'our $g=1; eval { { local $g=2; } die "x\n" }; print "$g\n";';
close $o;
my $json = qx($^X -Ilib -MO=-q,SoN,json $f 2>/dev/null);
sub exc ($w) { [ map { "$_->{op}#$_->{node} $_->{detail}" } grep { $_->{rule} eq 'exc' } SoN::Verify::verify($w)->{violations}->@* ] }

is exc( JSON::PP->new->decode($json) ), [], 'the closed local: clean';

# THE MUTATION: the inner block's restore taken off the memory chain to the
# die -- the local is then live there, and the eval's way out does not put it
# back.
{   my $w = JSON::PP->new->decode($json);
    my $nodes = $w->{methods}{'main::__PROGRAM__'}{nodes};
    my %by = map { $_->{id} => $_ } @$nodes;
    my %on_exc;
    for my $x ( grep { $_->{op} eq 'Exc' } @$nodes ) {
        my @q = ( $x->{id} );
        while ( defined( my $id = shift @q ) ) { next if $on_exc{$id}++; push @q, map { $_->{id} } grep { ( $_->{control_in} // -1 ) == $id } @$nodes }
    }
    my ($r) = grep {
        my $s = $by{ $_->{inputs}[1] // '' } // {};
        $_->{op} eq 'EntryWrite' && $s->{op} eq 'EntryDef' && defined $s->{mem_in} && !$on_exc{ $_->{id} }
    } @$nodes;
    ok $r, 'the wire has the inner restore';
    # (what followed the restore in memory follows what it followed)
    for my $y ( grep { $_ != $r } @$nodes ) {
        $y->{mem_in} = $r->{mem_in} if ( $y->{mem_in} // -1 ) == $r->{id};
    }
    my $v = exc($w);
    ok( scalar(@$v), 'the local left live at the die: rejected' ) or diag 'CLEAN';
    like $v->[0] // '', qr/does not put back the local of main:\$:g/, 'names the local';
}
done_testing;
