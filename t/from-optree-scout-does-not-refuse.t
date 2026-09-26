# ABOUTME: The scout pass discovers mutated slots; it builds no graph, so an
# ABOUTME: unlowerable construct in the body must not abort translation there.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir( CLEANUP => 1 );

sub graph_of ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
    unlink $f;
    return ( eval { JSON::PP->new->decode($j) }, $e );
}

# A REFUSAL IN THE SCOUT KILLS TRANSLATION BEFORE THE REAL PASS RUNS.
# _scout_mutated_targs builds a THROWAWAY factory and sim -- placeholder
# Constants for every live slot, a discarded MemStart -- purely to learn which
# slots the body mutates. It emits nothing that reaches the wire.
#
# So a `die` reached during scouting is a refusal about LOWERING, raised by a
# pass that is not lowering. Traced on
# `for my $i (1..6) { next if $i==2; next if $i==4; $s+=$i }`:
#
#     _walk_branch:11284 <- _walk_branch:9578 <- _walk_loop_body:7995
#       <- _scout_mutated_targs:8653 <- _translate_foreach_range:6252
#
# The second guard is reached by the SCOUT, and its refusal aborts the loop
# before the real pass -- which has @break_projs and a loop node and might
# well handle it.
#
# This is the shape recorded in [[a-guard-can-measure-the-wrong-quantity]]:
# the scout walks the body TWICE by design, and a guard that fires on the
# first walk measures the wrong pass.

subtest 'a second guarded next does not abort in the scout' => sub {
    my ( $data, $err ) = graph_of(<<'SRC');
my $s = 0;
for my $i (1 .. 6) {
    next if $i == 2;
    next if $i == 4;
    $s += $i;
}
print "$s\n";
SRC
    # THE REFUSAL NAMES ITS PASS, which is what makes this testable at all --
    # before the marker, a scout refusal and a real-pass refusal produced the
    # same message and no test could tell them apart.
    like $err, qr/GAP:/, 'it refuses' or diag $err;
    unlike $err, qr/slot-discovery scout/,
        'and the refusal is NOT raised by the scout'
        or diag $err;
};

# THE SCOUT MUST STILL FIND MUTATED SLOTS in a body it cannot fully walk.
# If the scout swallows an error and returns an EMPTY mutated set, the header
# builds no Phi for a slot the body writes -- which is a silent miscompile far
# worse than the refusal. So a loop whose body mutates a slot AND holds an
# unlowerable construct must not translate to a graph missing that Phi.
subtest 'a loop that does translate still gets its carried Phi' => sub {
    my ( $data, $err ) = graph_of(<<'SRC');
my $s = 0;
for my $i (1 .. 6) {
    next if $i == 2;
    $s += $i;
}
print "$s\n";
SRC
    ok $data && $data->{methods}{'main::__PROGRAM__'},
        'one guard translates' or diag($err), return;
    my @nodes = $data->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    my @phis  = grep { $_->{op} eq 'Phi' } @nodes;
    ok scalar(@phis) >= 2,
        'the accumulator and the induction variable both have Phis'
        or diag('phis = ' . scalar(@phis));
};

done_testing;
