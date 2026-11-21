# ABOUTME: chalk's verifier rows are held per graph: a recorded graph whose count
# ABOUTME: rises fails, a graph the record does not have is printed, not failed.
use v5.42.0;
use Test2::V0;
use lib 'tools/lib';
use WireRatchet qw(parse_graph_lines graph_line compare_graphs);

# perigrin, 2026-11-21: chalk's lib changes with every chalk-side stage, so
# its totals move with code nobody changed on the producer. The record names
# each graph; only a graph it names may not get worse.
my $record = parse_graph_lines(
    "chalk\t\@Chalk::A::old\tread-unversioned:field=2,memory-order-disagrees=1\n",
    "chalk\t\@Chalk::A::clean\t\n",
    "chalk2\t\@Chalk::A::old\tversion-off-chain=3\n",
);
is $record->{chalk}{'Chalk::A::clean'}, {}, 'a clean graph is recorded, with no rules';

my $got = {
    chalk => {
        'Chalk::A::old'   => { 'read-unversioned:field' => 3, 'memory-order-disagrees' => 1 },
        'Chalk::A::clean' => { 'read-unversioned:through-ref' => 1 },
        'Chalk::B::new'   => { 'read-unversioned:field' => 254 },
    },
    chalk2 => { 'Chalk::A::old' => { 'version-off-chain' => 2 } },
};
my $c = compare_graphs( $record, $got );

is [ sort { $a->[1] cmp $b->[1] } $c->{rose}->@* ], [
    [ 'chalk', 'Chalk::A::clean', 'read-unversioned:through-ref', 0, 1 ],
    [ 'chalk', 'Chalk::A::old',   'read-unversioned:field',       2, 3 ],
], 'a recorded graph that rises fails, a clean one too';
is $c->{new}, [ [ 'chalk', 'Chalk::B::new', { 'read-unversioned:field' => 254 } ] ],
    'a graph not in the record is new: printed, not a rise';
is $c->{fell}, [ [ 'chalk2', 'Chalk::A::old', 'version-off-chain', 3, 2 ] ], 'a fall is reported';
is $c->{gone}, [], 'every recorded graph was seen';

my $g2 = compare_graphs( $record, { chalk => {}, chalk2 => {} } );
is [ sort map { "$_->[0] $_->[1]" } $g2->{gone}->@* ],
    [ 'chalk Chalk::A::clean', 'chalk Chalk::A::old', 'chalk2 Chalk::A::old' ], 'a recorded graph not seen is gone';
is $g2->{rose}, [], '... and gone is not a rise';

is parse_graph_lines( graph_line( 'chalk', 'X::y', { b => 1, a => 2 } ) . "\n" )->{chalk}{'X::y'}, { a => 2, b => 1 },
    'graph_line writes what parse_graph_lines reads';
is graph_line( 'chalk', 'X::y', { a => 0 } ), "chalk\t\@X::y\t", 'a zero is not written';

done_testing;
