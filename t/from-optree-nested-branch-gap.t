# ABOUTME: A nested branch inside a branch arm never crashes the producer (zhi 019f34cc).
# ABOUTME: The void and/or handler must not misread a nested-branch join as an EXPR-while-COND loop back-edge.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# `if($c){ if($d){$a[0]=9} } $a[0]` -- the OUTER if's arm contains an inner if.
# The void and/or handler's loop-back-edge detector used to treat the inner
# branch's forward join (a visited op that is not the stop_addr) as a genuine
# `EXPR while COND` back-edge and descend into _translate_while_loop, which
# walked with a broken memory state and CRASHED building a Subscript with an
# undef memory input ("Can't call method consumers on an undefined value").
#
# The producer must never crash here. The fix: a true loop back-edge re-enters
# the condition head (an op visited BEFORE the arm walk); a nested-branch join
# is visited DURING the arm walk, so it is not a loop. A nested element store
# now lowers -- its round trip against perl is
# t/from-optree-an-element-store-in-a-nested-branch.t.

sub translate_err ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $cerr = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $cerr" if $cerr;
    my $err = dies { SoN::FromOptree->translate($cv) };
    return $err // '';
}

subtest 'a nested branch-store arm translates, never crashes on undef memory' => sub {
    my $err = translate_err('sub { my @a=(1,2,3); my $c=1; my $d=1; if($c){if($d){$a[0]=9}} $a[0] }');
    is($err, '', 'nested branch-store arm translates') or diag($err);
    unlike($err, qr/consumers on an undefined/,
        'not the pre-fix undef-memory crash');
};

subtest 'a nested scalar-store arm GAPs, never crashes' => sub {
    my $err = translate_err('sub { my $c=1; my $d=1; my $x=0; if($c){if($d){$x=9}} $x }');
    unlike($err, qr/consumers on an undefined/,
        'nested scalar-store arm does not crash on undef memory');
};

subtest 'a genuine EXPR-while-COND loop still translates (regression)' => sub {
    my $err = translate_err('sub { my $i=0; $i++ while $i<3; $i }');
    is($err, '', 'a real statement-modifier while loop is not misread as a GAP');
};

subtest 'a genuine block while loop still translates (regression)' => sub {
    my $err = translate_err('sub { my @a=(1,2,3); my $i=0; while($i<3){$a[$i]=$i; $i=$i+1} $a[0] }');
    is($err, '', 'a real block while loop still translates');
};

done_testing();
