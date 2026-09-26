# ABOUTME: `\(@a)` and `\(&x,$y)` are refgen -- mark-delimited and DISTRIBUTIVE,
# ABOUTME: one reference per element -- which `\@a`'s single srefgen is not.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub write_tmp ($src, $tag) {
    my $f = "$dir/$tag." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    return $f;
}

sub emit ($src) {
    my $f = write_tmp( $src, 'g' );
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    my $data = eval { JSON::PP->new->decode($j) } or return ( undef, 'no graph' );
    return ( undef, 'no program' ) unless $data->{methods}{'main::__PROGRAM__'};
    my $out = eval { SoN::Deparse->new->render($data) };
    return ( undef, ( $@ || 'refused' ) ) unless defined $out;
    return ( $out, undef );
}

sub runs ($src) {
    my $f = write_tmp( $src, 'r' );
    my $o = qx($^X $f 2>&1);
    unlink $f;
    return $o;
}

# TWO OPS, TWO MEANINGS, AND THE OPTREE SAYS WHICH. Measured:
#
#     my @r = \(@a);   refgen  lK/1   preceded by `pushmark sRM`
#     my $r = \@SRC;   srefgen sK/1   no mark
#
# `refgen` is MARK-DELIMITED and DISTRIBUTIVE -- it yields one reference per
# element of the list, not one reference to the list:
#
#     my @a=(10,20); my @r = \(@a);  -> 2 refs, ${$r[0]} is 10
#     my @a=(10,20); my @r = (\@a);  -> 1 ref,  ref($r[0]) is ARRAY
#
# Two different programs. Both reached the producer as `Ref(aggregate)` with
# `pop_count => 1`, so the distinction was lost in the graph and the emission
# printed nothing: `${$r[1]}` on a one-element array is `Not a SCALAR
# reference`.
#
# THE COUNT IS PART OF THE ANSWER, which is why the assertions read the LAST
# element rather than only the first. An implementation that emitted `(\@a)`
# gets `$r[0]` structurally wrong in a way that only shows when it is
# dereferenced, and gets `$r[1]` wrong by not having one at all.

# BLOCKED ON A WIRE ADDITION, not on a producer fix. `Ref` is a UnaryOp -- one
# input, one scalar reference out -- and a distributive ref has a different
# ARITY and a different RESULT KIND: N operands, a LIST of references. That is a
# new node rather than a flag on this one, and the wire is shared with chalk, so
# adding it is an agreement rather than a local change. Parked alongside the
# three already recorded in
# docs/plans/2026-09-26-three-wire-fields-chalk-must-agree.md.
#
# An attempt to pass `distributive => 1` on the existing node was reverted: the
# constructor rejects it, and forcing it would put a field on the wire that no
# consumer has a rule for -- a producer refusal removed in exchange for a
# consumer with no answer.
#
# TODO ON THE ASSERTIONS, not the subtest: a `todo` around the block amnesties
# its failures, the subtest then passes, and prove reports "TODO passed" --
# which reads as done.
subtest 'a distributive ref over an array' => sub {
    my $src = <<'SRC';
my @a = (10, 20);
my @r = \(@a);
print scalar(@r), " ${$r[0]} ${$r[1]}\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    my $todo = todo 'a distributive Ref is a new node kind, not a flag';
    is runs($out), runs($src), 'one reference per element';
};

subtest 'a distributive ref over a list of scalars' => sub {
    my $src = <<'SRC';
my ($x, $y) = (1, 2);
my @r = \($x, $y);
print scalar(@r), " ${$r[0]} ${$r[1]}\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    my $todo = todo 'a distributive Ref is a new node kind, not a flag';
    is runs($out), runs($src), 'one reference per operand';
};

# A PLAIN `\@a` MUST STAY ONE ARRAY REF. This is the srefgen case and the
# regression guard: `*c = \@SRC` aliases the array, and distributing it there
# would bind the LAST ELEMENT instead -- the miscompile the Ref renderer's
# aggregate exemption was written for.
subtest 'a plain array ref is not distributed' => sub {
    my $src = <<'SRC';
my @a = (10, 20);
my $r = \@a;
print ref($r), " @$r\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'still one ARRAY ref' or diag $out;
};

done_testing;
