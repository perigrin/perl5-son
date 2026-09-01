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

subtest 'a capturing anon sub names what it closes over' => sub {
    for my $case (
        [ 'sub { my $x = 5;  my $c = sub { $x };   $c }', '$x' ],
        [ 'sub { my $n = 0;  my $c = sub { $n++ }; $c }', '$n' ],
    ) {
        my ( $src, $var ) = $case->@*;
        my $sub = eval $src or die $@;
        ok( !lives { SoN::FromOptree->translate($sub) }, "refuses: $src" );
        my $err = $@;
        like( $err, qr/\Q$var\E/,
            "... naming the captured variable $var" );
    }
};

done_testing;
