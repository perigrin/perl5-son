# ABOUTME: The deparser reads a v2 wire (mem_in, mem_out) through SoN::Wire::as_v1, and
# ABOUTME: renders the program it renders from the same program's v1 wire.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'tools/lib';
use PvmCorpus qw(read_cases);

use SoN::Deparse;

# WHY (docs/plans/2026-11-20-wire-v2.md, stage 4). Wire v2 moves every memory
# operand out of `inputs` into `mem_in`, and a sub's exits merge their memory
# in a Phi only v2 writes. The deparser reads v1's shape; SoN::Wire::as_v1
# puts v2 back into it, so the deparser can take either until it reads v2
# natively (stage 11). Four corpus cases: a shift (a builtin version whose
# memory was an operand), early returns past a hash read, a sub whose exits
# merge their memory (the Phi v1 has no place for: kept, the deparser refused
# the sub), and a closure pushing onto a captured array (cells).

my $dir = tempdir( CLEANUP => 1 );
my @cases = read_cases('t/corpus/mdtest/pvm');

# The deparser names the variables it makes by node id (`$stale10`, `$eff9`),
# and v2 lists the nodes in another order (a node's memory is listed before
# it). Equal up to those names, by first appearance, is the same program.
sub alpha ($text) {
    my %name;
    my %n;
    return $text =~ s{([\$\@%])([A-Za-z][A-Za-z_]*?)(\d+)}{ $1 . ( $name{"$2$3"} //= $2 . '_' . ++$n{$2} ) }ger;
}

sub wire ( $src, $v ) {
    my $f = "$dir/c.pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,wire=$v,not_package=SoN $f 2>/dev/null);
    return JSON::PP->new->decode($j);
}

for my $n ( 18, 66, 129, 131 ) {
    my $c = $cases[ $n - 1 ];
    my ( $w1, $w2 ) = ( wire( $c->{src}, 1 ), wire( $c->{src}, 2 ) );
    is $w2->{version}, 2, "case $n: the v2 wire says so";
    my $d = SoN::Deparse->new;
    my $from1 = $d->render($w1);
    ok defined $from1, "case $n: v1 renders" or diag $d->gap;
    my $from2 = $d->render($w2);
    ok defined $from2, "case $n: v2 renders" or diag $d->gap;
    is alpha($from2), alpha($from1), "case $n: v2 renders as v1 does";
}

# as_v1 does not change the wire it is handed.
{
    require SoN::Wire;
    my $w2  = wire( $cases[17]{src}, 2 );
    my $was = JSON::PP->new->canonical->encode($w2);
    my $v1  = SoN::Wire::as_v1($w2);
    is JSON::PP->new->canonical->encode($w2), $was, 'as_v1 leaves its argument alone';
    is $v1->{version}, 1, 'as_v1 says version 1';
    ok !( grep { exists $_->{mem_in} || exists $_->{mem_out} } map { $_->{nodes}->@* } values $v1->{methods}->%* ),
        '... and names no memory edge';
}

done_testing;
