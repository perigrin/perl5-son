# ABOUTME: The deparser reads a v2 wire (mem_in, mem_out) through SoN::Wire::as_v1, and the
# ABOUTME: program it renders prints what perl prints for the source.
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
# puts v2 back into it, until it reads v2 natively (stage 11). Four corpus
# cases: a shift (a builtin version whose memory was an operand), early
# returns past a hash read, a sub whose exits merge their memory (the Phi v1
# has no place for: kept, the deparser refused the sub), and a closure
# pushing onto a captured array (cells).
#
# Until stage 6 each rendering was compared with the one of the same
# program's v1 wire (equal up to names made from node ids). Wire v1 is gone:
# what is left to hold is what the rendering does -- run, it prints the
# case's output.

my $dir = tempdir( CLEANUP => 1 );
my @cases = read_cases('t/corpus/mdtest/pvm');

sub wire ($src) {
    my $f = "$dir/c.pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    return JSON::PP->new->decode($j);
}

for my $n ( 18, 66, 129, 131 ) {
    my $c = $cases[ $n - 1 ];
    my $w = wire( $c->{src} );
    is $w->{version}, 2, "case $n: the wire is v2";
    my $d    = SoN::Deparse->new;
    my $text = $d->render($w);
    ok defined $text, "case $n: it renders" or diag( $d->gap ), next;
    my $f = "$dir/r.pl";
    open my $fh, '>', $f or die $!;
    print $fh $text;
    close $fh;
    is scalar qx($^X $f 2>&1), $c->{want}, "case $n: the rendering prints what perl prints";
}

# as_v1 does not change the wire it is handed.
{
    require SoN::Wire;
    my $w2  = wire( $cases[17]{src} );
    my $was = JSON::PP->new->canonical->encode($w2);
    my $v1  = SoN::Wire::as_v1($w2);
    is JSON::PP->new->canonical->encode($w2), $was, 'as_v1 leaves its argument alone';
    is $v1->{version}, 1, 'as_v1 says version 1';
    ok !( grep { exists $_->{mem_in} || exists $_->{mem_out} } map { $_->{nodes}->@* } values $v1->{methods}->%* ),
        '... and names no memory edge';
}

done_testing;
