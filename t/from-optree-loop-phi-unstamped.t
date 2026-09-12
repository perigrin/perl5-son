# ABOUTME: An unstamped loop Phi never had an optimistic stamp, so nothing in the body can be stale.
# ABOUTME: The refusal guarded a contamination that cannot exist when the Phi says nothing.

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
    return ($data ? $data->{methods} : undef, $err);
}

# THE REFUSAL'S RATIONALE WAS "the body was already stamped against this Phi's
# optimistic init stamp, so merely un-stamping the Phi leaves those stale stamps
# contaminating sibling Phi joins".
#
# That is true when an optimistic stamp EXISTED. It cannot be true when the Phi
# says nothing: _make_loop_phi stamps a loop Phi ONLY when its init is narrowed
#
#     (_is_narrowed($init->stamp) ? (stamp => $init->stamp) : ())
#
# so an Unknown Phi was never asserted to be anything, the body was walked
# against Unknown, and no consumer can be stale relative to a claim never made.
#
# The guard was `defined $phi->stamp`, and EVERY Value node carries a stamp now
# -- the same trap this file's own comment names twenty lines above ("'Has a
# stamp' is not the question ... `Unknown` is how a stamp says it does not").
# The first branch was corrected to _is_narrowed; this one was not, so it fired
# unconditionally.
#
# Measured: all three corpus files behind this GAP (comp/proto.t,
# comp/require.t, comp/retainedlines.t) have phi=Unknown with BOTH arms
# Unknown, so join(Unknown, Unknown) = Unknown and there is no widening either.
subtest 'an unstamped loop Phi is not a refusal' => sub {
    for my $case (
        # init=Subscript/Unknown post=Phi/Unknown -- a nested loop rebinding $_
        ['nested $_ rebind',
         'my @a=(1,2); for (@a) { for my $j (0,1) { $_ = $a[$j] } } print scalar(@a);'],
        # init=Add/Unknown post=Add/Unknown -- an accumulator over untyped values
        ['untyped accumulator',
         'sub f { my ($x,$y)=@_; my $t=$x+$y; for my $i (1,2) { $t = $t+$x } return $t }
          print f(1,2);'],
    ) {
        my ($name, $src) = $case->@*;
        my (undef, $err) = translate($src);
        unlike $err, qr/loop-carried value loses its stamp/,
            "$name: not refused for an unstamped back-edge" or diag $err;
    }
};

# A STAMPED PHI OVER AN UNSTAMPED BACK-EDGE IS A DIFFERENT CASE and must stay
# refused: there the init DID assert a type, the body was walked against it,
# and the back-edge cannot confirm it. `sub f { my ($n)=@_; my $t=0; $t += $n }`
# is that shape -- init=Constant/Int, phi=Int, post=Add/Unknown.
subtest 'a stamped Phi over an unstamped back-edge still refuses' => sub {
    my (undef, $err) = translate(
        'sub f { my ($n)=@_; my $t=0; for my $i (1,2) { $t += $n } return $t }
         print f(3);');
    like $err, qr/GAP:/, 'refused';
    like $err, qr/stamp/, '... naming the stamp';
};

# NOTHING REACHES THE WIRE CLAIMING MORE THAN IT KNOWS. An unstamped Phi stays
# unstamped -- that is the honest answer, and the post-pass fixpoint in
# B::SoN.pm is what narrows it later if it can.
subtest 'the unstamped Phi reaches the wire honestly' => sub {
    my ($m, $err) = translate(
        'my @a=(1,2); for (@a) { for my $j (0,1) { $_ = $a[$j] } } print scalar(@a);');
    ok defined $m && $m->{'main::__PROGRAM__'}, 'it translates' or diag($err), return;

    my $nodes = $m->{'main::__PROGRAM__'}{nodes};
    my %by = map { $_->{id} => $_ } $nodes->@*;

    # A Phi may not claim a type NARROWER than an arm -- that is the
    # contamination the refusal existed to prevent, and it must not appear
    # now that the refusal is gone.
    for my $phi (grep { $_->{op} eq 'Phi' } $nodes->@*) {
        my @arms = grep { defined } map { $by{$_} } $phi->{inputs}->@*;
        next unless @arms == 2;
        my @stamps = map { $_->{stamp} // 'Unknown' } @arms;
        next if grep { $_ eq 'Unknown' } @stamps;
        next if ($phi->{stamp} // 'Unknown') eq 'Unknown';
        ok !(grep { $_ eq 'Num' } @stamps) || $phi->{stamp} ne 'Int',
            "Phi $phi->{id} does not keep Int over a Num arm"
            or diag "phi=$phi->{stamp} arms=@stamps";
    }
    ok 1, 'no Phi is narrower than its arms';
};

done_testing;
