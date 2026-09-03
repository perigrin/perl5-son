# ABOUTME: A single-branch `if` whose arm stores to a FIELD must build real control flow.
# ABOUTME: Without an If the store runs unconditionally -- the guard vanishes silently.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub graphs_of ($src, $pkgs) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,$pkgs $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    return $data->{methods};
}

sub ops_of ($g) {
    return map { $_->{op} } $g->{nodes}->@*;
}

# A one-armed `if` compiles to an `and` op, NOT a cond_expr -- measured:
#
#   6  <|> and(other->7) vK/1
#   9      <2> add[$n:FAKE:] vK/TARGMY,2
#
# The `and`/`or` handler's void-branch gate (FromOptree.pm:451-454) lists
# _arm_has_element_store, _arm_has_void_call and _arm_has_die -- but NOT
# _arm_has_field_store. So a field store in a one-armed `if` builds no If at
# all: the store lands on the base control chain and runs unconditionally.
#
# THIS IS THE SAME DEFECT SHAPE the `die` entry in that list was added to fix,
# and the comment there records it: "It was not listed here ... so no If was
# built ... and the statement after the branch ran unconditionally."
# _arm_has_field_store is the next one missing from the same list.
#
# The cond_expr handler (:6867-6871) DOES call all four, which is why the
# two-armed if/else form works and made this look covered.
#
# Measured, `method bump { if ($n > 5) { $n = $n + 3 } return $n }`:
#   n=10   perl 13   chalk 10      <- the guarded store is DROPPED
#   n=1    perl  1   chalk  1      <- agrees, but only because the guard is
#                                     false and dropping the store is
#                                     coincidentally right
# The false-polarity agreement is why a one-sided test reads this as green.

my $CLS = <<'PERL';
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class C {
    field $n :param = 0;
    method bump { if ($n > 5) { $n = $n + 3 } return $n }
}
package main;
say(C->new(n => 10)->bump);
PERL

subtest 'a field store in a one-armed if is guarded by real control flow' => sub {
    my $m = graphs_of($CLS, 'package=main,package=C');
    ok($m, 'producer emitted a graph set') or return;
    my $g = $m->{'C::bump'};
    ok($g, 'the method graph is present') or return;

    my @ops = ops_of($g);

    # ASSERT POSITIVELY. "no Assign" would be satisfied by any unrelated
    # defect that happens to drop the store; what must be true is that the
    # store EXISTS and is GUARDED.
    my $has_assign = grep { $_ eq 'Assign' } @ops;
    my $has_if     = grep { $_ eq 'If' } @ops;

    ok($has_assign, 'the field store is present in the graph')
        or diag('ops: ' . join(' ', @ops));

    ok($has_if,
        'an If node guards it -- without one the store runs unconditionally')
        or diag('ops: ' . join(' ', @ops));
};

# THE CONTROL, and it is the one that matters. Both of these already worked
# before the fix, and each differs from the broken case in exactly one way --
# so if a fix breaks either, it fixed the wrong thing.
subtest 'the two shapes that already worked still do' => sub {
    my $two_armed = $CLS =~ s/\{ \$n = \$n \+ 3 \}/{ \$n = \$n + 3 } else { \$n = 0 }/r;
    my $m1 = graphs_of($two_armed, 'package=main,package=C');
    ok($m1 && $m1->{'C::bump'}, 'two-armed if/else produced a graph') or return;
    ok(scalar(grep { $_ eq 'If' } ops_of($m1->{'C::bump'})),
       'two-armed if/else builds an If (it reaches the cond_expr handler)');

    my $void_arm = $CLS =~ s/\{ \$n = \$n \+ 3 \}/{ print qq{big\\n} }/r;
    my $m2 = graphs_of($void_arm, 'package=main,package=C');
    ok($m2 && $m2->{'C::bump'}, 'one-armed if with a void print produced a graph') or return;
    ok(scalar(grep { $_ eq 'If' } ops_of($m2->{'C::bump'})),
       'a void-call arm builds an If (_arm_has_void_call IS in the list)');
};

done_testing;
