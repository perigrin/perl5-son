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

# THE STAMP MUST BE THE HONEST ONE. An Int claim over a back-edge that floors
# to Scalar is a narrower assertion than the truth; this pins the widening
# rather than just the round trip.
subtest 'the loop Phi widens to the join rather than keeping Int' => sub {
    my ( $data, $err ) = graph_of(
        'for ($i = 0; $i <= 3; $i++) { print "i=$i\n" }' );
    ok $data, 'it translates' or diag($err), return;

    my @n = ( $data->{methods}{'main::__PROGRAM__'}{nodes} // [] )->@*;
    my @phi = grep { ( $_->{op} // '' ) eq 'Phi' } @n;
    ok scalar(@phi), 'a loop Phi exists' or return;

    is [ map { $_->{stamp} } @phi ], bag { item 'Scalar'; etc; },
        'the carried Phi is Scalar, not a stale Int';
};

done_testing;
