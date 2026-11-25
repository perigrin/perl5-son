# ABOUTME: The deparser takes a node's memory input from the wire's named mem_in (as_v1's
# ABOUTME: memory_input mark), not from a table of how many inputs each kind has.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Deparse;
use SoN::Wire;

# %MEM_MIN_INPUTS said how many inputs of each kind were values, and the last
# one past that, if it looked like memory, was memory: positional memory (final
# audit, clause 3). A kind missing from it counted its memory edge as a value
# and bound the store it named -- Exists once, "no rule for value node
# `EntryWrite`" on comp/require.t.
ok !defined *SoN::Deparse::MEM_MIN_INPUTS{HASH} || !%SoN::Deparse::MEM_MIN_INPUTS, 'no table of input counts';

my $dir = tempdir( CLEANUP => 1 );
my $src = 'our $g = "a\n"; my $n = chomp $g; print "$n|$g|\n";';
open my $o, '>', "$dir/c.pl" or die $!;
print $o $src, "\n";
close $o;
my $w = decode_json( scalar qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $dir/c.pl 2>/dev/null) );
my $want = scalar qx($^X $dir/c.pl);

sub run_of ($wire) {
    my $d   = SoN::Deparse->new;
    my $out = $d->render($wire) // return 'GAP ' . $d->gap;
    open my $p, '>', "$dir/r.pl" or die $!;
    print $p $out;
    close $p;
    return scalar qx($^X $dir/r.pl 2>&1);
}
is run_of($w), $want, 'the program renders to perl\'s answer';

# The Chomp, given the version it reads as its named mem_in (a kind the table
# never listed): as_v1 appends it and marks it, and the deparser leaves it out.
my ($chomp) = grep { $_->{op} eq 'Chomp' } $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
my ($read)  = map { my $i = $_; grep { $_->{id} == $i } $w->{methods}{'main::__PROGRAM__'}{nodes}->@* } $chomp->{inputs}[0];
$chomp->{mem_in} = $read->{mem_in};
# (an operand, as the producer marks one -- audit 2: as_v1 reads the mark)
$chomp->{mem_operand} = JSON::PP::true;
my ($v1c) = grep { $_->{op} eq 'Chomp' } SoN::Wire::as_v1($w)->{methods}{'main::__PROGRAM__'}{nodes}->@*;
ok $v1c->{fields}{memory_input}, 'as_v1 marks the memory it appended';
is run_of($w), $want, '... and the deparser reads it as memory, not a value';

done_testing;
