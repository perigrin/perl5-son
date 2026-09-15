# ABOUTME: Every node the producer gives a memory input must be in the trim table.
# ABOUTME: A missing entry counts the memory edge as a value and binds a store.

use v5.42.0;
use Test2::V0;
use lib 'lib';
use SoN::Deparse;

# %MEM_MIN_INPUTS tells the reads scan how many of a node's inputs are real
# operands, so the TRAILING memory edge is not counted as a value. A kind
# missing from it binds the node that produced its memory -- and then asks to
# render a store as an expression:
#
#     GAP: no rule for value node `EntryWrite`
#
# Measured on comp/require.t, where `Exists` had the memory shape its own
# comment documents ([container, key, memory]) but no table entry, while
# `Delete` -- the same shape one operator over -- did.
#
# SCRAPED FROM THE PRODUCER, not from a second hand-kept list. The question is
# "which kinds does FromOptree build with a memory input", and only FromOptree
# can answer it; a list here would drift exactly as the table did.
my $src = do {
    open my $fh, '<', 'lib/SoN/FromOptree.pm' or die $!;
    local $/; <$fh>;
};

my %builds_with_memory;
while ( $src =~ /make\(\s*'(\w+)'\s*,\s*\n?\s*inputs\s*=>\s*\[([^\]]*)\]/gs ) {
    my ( $kind, $inputs ) = ( $1, $2 );
    $builds_with_memory{$kind} = 1 if $inputs =~ /memory/;
}

ok scalar(keys %builds_with_memory) > 5,
    'the scrape found the construction sites'
    or diag "found: " . join( ' ', sort keys %builds_with_memory );

subtest 'every memory-carrying kind is in the trim table' => sub {
    my @missing = grep { !exists $SoN::Deparse::MEM_MIN_INPUTS{$_} }
                  sort keys %builds_with_memory;
    is \@missing, [],
        'no kind the producer gives memory is absent from %MEM_MIN_INPUTS'
        or diag "MISSING: @missing";
};

done_testing;
