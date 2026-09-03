# ABOUTME: An anon sub's REFUSAL must say whether it closes over anything --
# ABOUTME: capture is statically visible, and the two cases need different work.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;

# BOTH SHAPES STILL REFUSE, and this test does not change that. What it pins is
# that the refusal DISTINGUISHES them, because they need different work and a
# single message hides which one a corpus file actually hit.
#
# Capture is decidable at compile time: a captured pad name carries the OUTER
# flag (0x1000000) in the anon CV's padlist, while an own lexical is 0x0.
# Measured:
#
#     sub { 1; }              captures=[]     no closure
#     sub { my $y=1; $y }     captures=[]     own lexical, NOT a capture
#     sub { $_[0]*2 }         captures=[]     @_ is not a capture
#     my $x=5; sub { $x }     captures=[$x]   closure
#     my $c=0; sub { $c++ }   captures=[$c]   closure
#
# The middle case is why "does the pad have names" is the wrong test: it counts
# an own lexical as a capture and would refuse a body that needs nothing from
# its enclosing scope.

subtest 'a non-capturing anon sub lowers' => sub {
    for my $src (
        'sub { my $c = sub { 1; }; $c }',
        'sub { my $c = sub { my $y = 1; $y }; $c }',
        'sub { my $c = sub { $_[0] * 2 }; $c }',
    ) {
        my $graph;
        my $sub = eval $src or die $@;
        ok( lives { $graph = SoN::FromOptree->translate($sub) },
            "lowers: $src" ) or diag($@);

        # The middle case is the one that matters: `my $y = 1` is an OWN
        # lexical, not a capture, and a test keyed on "does the pad have
        # names" would refuse it. It must lower like the others.
        my ($anon) = grep { $_->operation eq 'AnonSub' } $graph->nodes->@*;
        ok( $anon && defined $anon->name,
            '... to an AnonSub naming its body' );
    }
};

# A CAPTURING ANON SUB LOWERS TO A CELL. It used to refuse, on the grounds
# that a capture had no wire representation -- true when written, and no longer
# so. The capture is a SHARED MUTABLE CELL: measured on 5.42.0,
#
#     my $n=5; my $c = sub { $n }; $n = 99;   $c->() is 99
#
# so the closure holds the VARIABLE, not a copy of its value. MakeCell in the
# enclosing scope is the storage, and the AnonSub takes it as an input.
subtest 'a capturing anon sub builds a cell naming what it closes over' => sub {
    for my $case (
        [ 'sub { my $x = 5;  my $c = sub { $x };   $c }', '$x', 0 ],
        [ 'sub { my $n = 0;  my $c = sub { $n++ }; $c }', '$n', 1 ],
    ) {
        my ( $src, $var, $written ) = $case->@*;
        my $sub = eval $src or die $@;
        my $graph;
        ok( lives { $graph = SoN::FromOptree->translate($sub) },
            "lowers: $src" ) or diag($@);
        next unless $graph;

        my ($cell) = grep { $_->operation eq 'MakeCell' } $graph->nodes->@*;
        ok( $cell, "... building a MakeCell for $var" ) or next;
        is( $cell->cell_name, $var, "... which names $var" );

        # WHETHER THE CAPTURE IS WRITTEN is what tells a consumer the cell is
        # load-bearing rather than eligible to be replaced by its value. `$n++`
        # is one of FOUR write forms and the one a naive `look for sassign`
        # check misses -- perl compiles it to preinc over an OPf_MOD padsv,
        # with no assignment op anywhere.
        is( !!$cell->captured_written, !!$written,
            "... and reports captured_written correctly" );

        # The cell is the closure's environment, so it must reach the AnonSub.
        my ($anon) = grep { $_->operation eq 'AnonSub' } $graph->nodes->@*;
        ok( $anon && grep({ $_ == $cell } $anon->inputs->@*),
            '... and the AnonSub takes the cell as an input' );
    }
};

done_testing;
