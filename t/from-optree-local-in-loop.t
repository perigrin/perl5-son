# ABOUTME: `local` inside a loop body restores at the ITERATION boundary, which is what perl does.
# ABOUTME: The body walk models one iteration, so the unstack it stops at is that boundary.

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

# `local` in a loop body restores ONCE PER ITERATION, and that is not a
# problem to be solved -- it is what perl does. Measured:
#
#     our $g = "outer";
#     for my $i (1,2) { print "top:$g "; local $g = "iter"; print "set:$g " }
#     print "| after:$g"
#       perl: top:outer set:iter top:outer set:iter | after:outer
#
# The SECOND iteration reads `outer`, not `iter`: the restore already happened.
# The refusal's stated reason had the semantics backwards -- per-iteration IS
# the correct timing, and the body walk models exactly one iteration, so the
# unstack it already stops at is that boundary.
subtest 'local in a for loop body lowers' => sub {
    my ($g, $err) = translate(<<'SRC');
our $g = "outer";
for my $i (1,2) { local $g = "iter"; }
print "$g\n";
SRC
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;
    ok defined $g, 'it translates' or return;

    my @ops = map { $_->{op} } $g->{nodes}->@*;
    ok scalar(grep { $_ eq 'Loop' } @ops), 'the loop is in the graph';
};

# THE READ AFTER THE LOOP MUST SEE THE OUTER BINDING. If the restore never
# fires, the print resolves to the localised value and the graph says "iter"
# where perl says "outer" -- a silent miscompile, not a missing optimisation.
subtest 'a read after the loop sees the restored binding' => sub {
    my ($g, $err) = translate(<<'SRC');
our $g = "outer";
for my $i (1,2) { local $g = "iter"; }
print "$g\n";
SRC
    ok defined $g, 'it translates' or return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my ($print) = grep { $_->{op} eq 'Print' } $g->{nodes}->@*;
    ok defined $print, 'the print is in the graph' or return;

    # Walk back from the Print to whatever Constant feeds it.
    my @seen;
    my @queue = $print->{inputs}->@*;
    my %done;
    while (my $id = shift @queue) {
        next if $done{$id}++;
        my $n = $by{$id} or next;
        push @seen, $n->{fields}{value} // ''
            if $n->{op} eq 'Constant';
        push @queue, $n->{inputs}->@*;
    }
    ok scalar(grep { $_ eq 'outer' } @seen),
        'the print reaches the outer binding, not the localised one'
        or diag "constants reached: @seen";
    ok !scalar(grep { $_ eq 'iter' } @seen),
        '... and not the localised one'
        or diag "constants reached: @seen";
};

# while and foreach reach the loop-body walker by different routes.
subtest 'local lowers in every loop kind' => sub {
    for my $case (
        ['while',   'our $g=1; my $i=0; while ($i<2) { local $g = $i; $i++; }'],
        ['foreach', 'our $g=1; my @a=(1,2); for my $x (@a) { local $g = $x; }'],
        ['special', 'for my $i (1,2) { local $^W = $i; }'],
        ['aggregate','our @a=(1); for my $i (1,2) { local @a = ($i); }'],
    ) {
        my ($name, $src) = $case->@*;
        my (undef, $err) = translate($src);
        unlike $err, qr/GAP:/, "$name: not refused" or diag $err;
    }
};

done_testing;
