# ABOUTME: a C-style for over an undeclared package scalar carries an Unknown back-edge.
# ABOUTME: the EntryDef's floor is knowable from its sigil, so the Phi can widen honestly.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub run_perl ($src) {
    my $f = "$dir/r." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $f 2>&1);
    unlink $f;
    return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>$dir/err);
    my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
    unlink $f;
    return ( eval { JSON::PP->new->decode($j) }, $e );
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my ( $data, $err ) = graph_of($src);
    unless ( $data && $data->{methods}{'main::__PROGRAM__'} ) {
        fail "$name: translates";
        diag $err;
        return;
    }
    my $d   = SoN::Deparse->new;
    my $out = eval { $d->render($data) };
    unless ( defined $out ) {
        my $g = $d->gap // $@ // '(no reason)';
        $g =~ s/\n.*//s;
        fail "$name: renders";
        diag $g;
        return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# THE DEFECT. `for ($i = 0; $i <= 3; $i++)` with an UNDECLARED package scalar
# gives the loop Phi an Int init (from `$i = 0`) and an Unknown back-edge:
#
#     Phi/Int   back-edge = Add(EntryDef/Unknown, Constant/Int)
#
# The EntryDef is Unknown because a package scalar's stamp comes from the
# POST-PASS (_floor_package_globals), while _patch_loop_phi runs during the
# walk. So the walk could not compute a join and refused -- the same
# phase-ordering shape as the glob binding.
#
# THE FLOOR IS KNOWABLE NOW, from the sigil alone: `$` floors to Scalar. And
# the honest join is join(Int, Scalar) = Scalar, so the Phi must WIDEN -- the
# path that already exists -- rather than keep an Int claim the back-edge
# will contradict. Keeping Int would be a narrower claim than the truth,
# which is the "stale stamps contaminating sibling joins" the refusal warns
# about.
#
# This is cmd/for.t's FIRST loop, so the whole file stood behind it.
# TWO DEFECTS, AND THE SECOND NEEDED A THIRD FACT TO FIX.
#
# Defect 2 was that the emitted loop never terminated: _loop_invariant_roots
# hoisted `my $inv = $main::i` to entry while the body wrote $main::i.
#
# Suppressing the hoist whenever the body writes the variable BROKE THE OTHER
# LOOP FORM -- t/deparse-loop-bound-is-evaluated-once.t, because perl's forms
# genuinely disagree:
#
#     $n=2; foreach my $i (1..$n) { $n = 10 }    2 iterations, bound FIXED
#     $n=2; for ($i=0; $i<$n; $i++) { $n = 4 }   4 iterations, RE-READ
#
# Three graph-derived discriminators failed (see SoN::IR::Node::Loop's
# `bound`), so the Loop now carries which form it is and hoisting keys on
# that.
round_trips( <<'SRC', 'a C-style for over a package scalar' );
for ($i = 0; $i <= 3; $i++) { print "i=$i\n" }
SRC

round_trips( <<'SRC', 'the induction value survives the loop' );
for ($i = 0; $i <= 3; $i++) { }
print "$i\n";
SRC

# A LEXICAL INDUCTION VARIABLE IS UNAFFECTED -- its stamp is known during the
# walk, so the Phi keeps its narrow type and nothing widens.
round_trips( <<'SRC', 'a C-style for over a lexical is unchanged' );
for (my $i = 0; $i <= 3; $i++) { print "i=$i\n" }
SRC

# THE STAMP MUST BE THE HONEST ONE -- never NARROWER than what the back-edge
# proves. That is the fact; `Scalar` was only ever the shape that carried it.
#
# This subtest asserted `bag { item 'Scalar' }` and failed from 2026-09-27,
# because the producer got MORE precise rather than less. Its own premise, in
# the header above, was "the EntryDef is Unknown because a package scalar's
# stamp comes from the POST-PASS while _patch_loop_phi runs during the walk" --
# and so join(Int, Unknown) had to widen to the sigil floor, Scalar.
#
# The read is now stamped Int at the point the Phi is built (measured:
# `10 EntryDef stamp=Int`), so the back-edge `Add(Int, Int)` is Int and the
# honest join is join(Int, Int) = Int. Demanding Scalar now demands a WIDER
# stamp than the truth, which is the same defect the original assertion
# existed to prevent, with the sign flipped.
#
# So the assertion is the fact: the carried Phi's stamp must be a type the
# back-edge satisfies, and never Unknown. Both Int and Scalar pass; a Str or an
# unstamped Phi does not.
# SINCE 2026-11-19 THERE IS NO SUCH PHI. A package scalar the program writes
# lives in memory (audit W1: a value Phi is a copy no callee's store reaches),
# so the loop carries it on its MEMORY Phi and each read is an EntryDef at a
# memory version. What this test held still holds, moved to where the value
# now is: the read in the loop is stamped honestly, never Unknown.
subtest 'the loop reads $i through memory, with an honest stamp' => sub {
    my ( $data, $err ) = graph_of(
        'for ($i = 0; $i <= 3; $i++) { print "i=$i\n" }' );
    ok $data, 'it translates' or diag($err), return;

    my @n = ( $data->{methods}{'main::__PROGRAM__'}{nodes} // [] )->@*;
    my %by_id = map { $_->{id} => $_ } @n;
    my ($loop) = grep { $_->{op} eq 'Loop' } @n;
    my @phi = grep { $_->{op} eq 'Phi' && ( $_->{fields}{region} // -1 ) == $loop->{id} } @n;
    is [ grep { !$_->{fields}{memory} } @phi ], [], 'no value Phi carries $i';
    my ($mem) = grep { $_->{fields}{memory} } @phi;
    ok $mem, 'the loop has a memory Phi' or return;

    my @reads = grep { $_->{op} eq 'EntryDef' && ( $_->{fields}{symbol} // '' ) eq 'i'
                       && ( $_->{inputs} // [] )->@* && $_->{inputs}[0] == $mem->{id} } @n;
    ok scalar(@reads), '$i is read at the loop\'s memory Phi' or return;
    for my $r (@reads) {
        my $st = $r->{stamp} // 'Unknown';
        ok $st ne 'Unknown', "read $r->{id} is stamped, not Unknown (got $st)";
    }
};

done_testing;
