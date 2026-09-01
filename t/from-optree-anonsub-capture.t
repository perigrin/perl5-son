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

subtest 'a non-capturing anon sub refuses without blaming closure' => sub {
    for my $src (
        'sub { my $c = sub { 1; }; $c }',
        'sub { my $c = sub { my $y = 1; $y }; $c }',
        'sub { my $c = sub { $_[0] * 2 }; $c }',
    ) {
        my $sub = eval $src or die $@;
        my $err;
        ok( !lives { SoN::FromOptree->translate($sub) },
            "still refuses: $src" );
        $err = $@;
        like( $err, qr/GAP/, '... as a GAP' );
        # Match the CLAIM, not the word: the non-capturing message legitimately
        # says "it captures nothing", and a blunt /captur/ rejects its own
        # correct wording.
        unlike( $err, qr/closing over/i,
            '... and does not claim it closes over anything' );
        like( $err, qr/captures nothing/i,
            '... but does say the body is capture-free' );
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
