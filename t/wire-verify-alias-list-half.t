# ABOUTME: V12's alias-list half (audit 2, K3): a foreach/map/grep item read per pass as a value must not
# ABOUTME: be used after a store in that pass that may reach its list; B::SoN's wires keep it, a broken one fails.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

# THE DEFECT (second final audit, class K3): `sub z { $a[0] = 7 } for my $x
# (@a) { z(); print $x }` printed 12 for perl's 72. The pass's read of the
# item, `Subscript [@a, i]` at the loop's memory Phi, was used by the print
# after the Call that stores @a. V12 asked that question of a call's
# arguments only.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub wire ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json $f 2>/dev/null);
    return $json ? JSON::PP->new->decode($json) : undef;
}
sub v12 ($w) { [ grep { $_->{rule} eq 'alias-not-private' } SoN::Verify::verify($w)->{violations}->@* ] }

my %src = (
    pa69 => 'my @a=(1,2); sub z { $a[0]=7 } for my $x (@a) { z(); print $x } print "\n";',
    qc09 => 'my @a=(1,2); sub z { $_++ for @a } for my $x (@a) { z(); print $x } print "\n";',
    before => 'my @a=(1,2); sub z { $a[0]=7 } for my $x (@a) { print $x; z() } print "\n";',
    other  => 'my @a=(1,2); my @b=(3); sub z { $b[0]=7 } for my $x (@a) { z(); print $x } print "\n";',
    carried => 'my @a=(1,2); my $s=""; sub z { 1 } for my $x (@a) { z(); $s .= $x } print "$s\n";',
);
for my $t ( sort keys %src ) {
    my $w = wire( $src{$t} ) or do { fail "$t compiles"; next };
    is [ map { "$_->{op}#$_->{node} $_->{detail}" } SoN::Verify::verify($w)->{violations}->@* ], [], "$t: clean";
}

# THE MUTATION: pa69's print reads the item at the loop's memory Phi again,
# as B::SoN wrote it before audit 2.
{   my $w = wire( $src{pa69} );
    my $nodes = $w->{methods}{'main::__PROGRAM__'}{nodes};
    my %by = map { $_->{id} => $_ } @$nodes;
    my ($loop) = grep { $_->{op} eq 'Loop' } @$nodes;
    my ($mphi) = grep { $_->{op} eq 'Phi' && $_->{fields}{memory} && $_->{fields}{region} == $loop->{id} } @$nodes;
    my ($iphi) = grep { $_->{op} eq 'Phi' && !$_->{fields}{memory} && $_->{fields}{region} == $loop->{id} } @$nodes;
    my ($list) = grep { $_->{op} eq 'PadAccess' && ( $_->{fields}{symbol} // '' ) eq 'a' && !defined $_->{mem_in} } @$nodes;
    my ($print) = grep { $_->{op} eq 'Print' && ( $by{ $_->{inputs}[0] }{op} // '' ) eq 'Coerce' } @$nodes;
    ok $loop && $mphi && $iphi && $list && $print, 'pa69 has its loop, list and print';
    my $id = 1 + ( sort { $b <=> $a } map { $_->{id} } @$nodes )[0];
    push @$nodes, { id => $id, op => 'Subscript', inputs => [ $list->{id}, $iphi->{id} ], mem_in => $mphi->{id}, fields => { kind => 'array' }, stamp => 'Scalar' };
    $by{ $print->{inputs}[0] }{inputs}[0] = $id;
    my $v = v12($w);
    ok( scalar(@$v), 'the item read at the pass start, used after the call: rejected' )
        or diag join '; ', map { "$_->{op}#$_->{node} $_->{rule}" } SoN::Verify::verify($w)->{violations}->@*;
    like $v->[0]{detail} // '', qr/per-pass item of elem:my:\@a .* after Call/, 'names the item and the call';
}

done_testing;
