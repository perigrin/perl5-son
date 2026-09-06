# ABOUTME: A block eval inside an if/else arm lowers, as it already does in a loop body.
# ABOUTME: The arm walker is a THIRD walker and needed the same entertry dispatch.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub translate ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $err = qx($^X -Ilib -MO=SoN,json,package=main $file 2>&1 >/dev/null);
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) };
    return ($data ? $data->{methods}{'main::__PROGRAM__'} : undef, $err);
}

# `eval { ... }` is entertry/leavetry, and the walker has THREE walks that must
# each know it: the main one, the loop body, and the branch arm. The first two
# dispatch to _handle_entertry; the arm walk did not, so it stopped at the
# entertry and the caller reported the symptom rather than the cause:
#
#     GAP: untranslatable op inside an if/else arm (arm stopped at `entertry`)
#
# The and/or path reported the same cause as "did not converge", which is why
# `if ($x) { eval {...} }` and `unless ($x) { eval {...} }` gave three different
# messages for one missing dispatch.
subtest 'a block eval in an if/else arm lowers' => sub {
    for my $case (
        ['if arm',    'my $x=1; if ($x) { my $r = eval { 1 }; print $r } print "d";'],
        ['else arm',  'my $x=0; if ($x) { print 1 } else { my $r = eval { 2 }; print $r }'],
        ['both arms', 'my $x=1; if ($x) { eval { 1 } } else { eval { 2 } } print "d";'],
        ['ternary',   'my $x=1; my $r = $x ? eval { 1 } : 2; print $r;'],
        ['unless',    'my $x=0; unless ($x) { my $r = eval { 1 }; print $r } print "d";'],
        ['void eval', 'my $x=1; if ($x) { eval { die "z" }; } print "d";'],
    ) {
        my ($name, $src) = $case->@*;
        my (undef, $err) = translate($src);
        unlike $err, qr/GAP:/, "$name: not refused" or diag $err;
    }
};

# THE EVAL'S TWO OUTCOMES MUST BOTH REACH THE GRAPH, inside the arm as much as
# anywhere else: the body's value, or the undef a caught die yields.
subtest 'the eval still merges its outcomes inside an arm' => sub {
    my ($g, $err) = translate(<<'SRC');
my $x = 1;
if ($x) { my $r = eval { 42 }; print $r }
print "d";
SRC
    ok defined $g, 'it translates' or diag($err), return;

    my @ops = map { $_->{op} } $g->{nodes}->@*;
    ok scalar(grep { $_ eq 'Phi' } @ops),
        'the eval merges its body value with the undef of a caught die'
        or diag "ops: @ops";
};

# A DYING BODY PUSHES NO VALUE -- `die` builds an Unwind and yields nothing --
# so there is one arm, not two, and no Phi for it.
subtest 'a dying eval in an arm builds its Unwind' => sub {
    my ($g, $err) = translate(<<'SRC');
my $x = 1;
if ($x) { eval { die "boom" }; print "caught" }
print "d";
SRC
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;
    ok defined $g, 'it translates' or return;

    my @ops = map { $_->{op} } $g->{nodes}->@*;
    ok scalar(grep { $_ eq 'Unwind' } @ops),
        'the die builds its Unwind inside the arm'
        or diag "ops: @ops";
};

done_testing;
