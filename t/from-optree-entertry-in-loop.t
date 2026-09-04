# ABOUTME: A block eval inside a loop body lowers, rather than being refused as an unhandled branch.
# ABOUTME: The loop body is walked by a separate walker that refuses every branch op it lacks a case for.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub translate ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $err  = qx($^X -Ilib -MO=SoN,json,package=main $file 2>&1 >/dev/null);
    my $out  = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) };
    return ($data ? $data->{methods}{'main::__PROGRAM__'} : undef, $err);
}

# `eval { ... }` compiles to entertry/leavetry, which is a registered BRANCH op.
# The loop-body walker is a SEPARATE walker from the main one and refuses every
# branch it has no case for -- so a block eval that lowers fine at statement
# level was refused the moment it appeared inside any loop. Measured: `for`,
# `while` and `foreach` over an array all refused; `eval STRING` did not,
# because that is entereval, a different op.
subtest 'a block eval inside a for loop lowers' => sub {
    my ($g, $err) = translate(<<'SRC');
for my $i (1,2) { my $r = eval { $i }; print "$r\n"; }
SRC
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;
    ok defined $g, 'it translates' or return;

    my @ops = map { $_->{op} } $g->{nodes}->@*;
    ok scalar(grep { $_ eq 'Loop' } @ops), 'the loop is in the graph';

    # THE EVAL'S TWO OUTCOMES MUST BOTH BE THERE. A body value and the undef a
    # caught die yields, merging at a Region -- the same shape the statement
    # level builds. A Region alone would not prove it: the loop has its own.
    ok scalar(grep { $_ eq 'Phi' } @ops),
        'the eval merges its body value with the undef of a caught die'
        or diag "ops: @ops";
};

# A body that ALWAYS throws pushes no value -- `die` builds an Unwind and
# yields nothing -- but the eval still HAS a result, and perl says it is undef.
subtest 'a block eval that dies inside a loop lowers' => sub {
    my ($g, $err) = translate(<<'SRC');
for my $i (1,2) { eval { die "x" }; print $@; }
SRC
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;
    ok defined $g, 'it translates' or return;

    my @ops = map { $_->{op} } $g->{nodes}->@*;
    ok scalar(grep { $_ eq 'Unwind' } @ops),
        'the die builds its Unwind inside the loop'
        or diag "ops: @ops";
};

# while and foreach reach the loop-body walker by different routes, so each is
# its own case rather than assumed from the `for` one.
subtest 'a block eval lowers in every loop kind' => sub {
    for my $case (
        ['while',   'my $i=0; while ($i<2) { my $r = eval { $i }; $i++; }'],
        ['foreach', 'my @a=(1,2); for my $x (@a) { my $r = eval { $x }; }'],
    ) {
        my ($name, $src) = $case->@*;
        my (undef, $err) = translate($src);
        unlike $err, qr/GAP:/, "$name: not refused" or diag $err;
    }
};

done_testing;
