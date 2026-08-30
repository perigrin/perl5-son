# ABOUTME: A value-context `&&`/`||` inside an if/else arm builds an And/Or node
# ABOUTME: -- the same value the main walk builds, not a GAP.
use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub ops_of ($g, $op) { return grep { $_->operation eq $op } $g->nodes->@* }

# THE GAP, and how narrow it is. A value-context `||` lowers to a single
# operand-returning `Or` node at the top level -- the main walk has built that
# since the logical.md corpus cases. Inside an if/else ARM it GAPped, because
# _walk_branch has no and/or handler at all: the arm stopped at the `or`, failed
# to reach the join, and the arm-walker's "untranslatable op" refusal fired.
#
#     c  <|> or(other->d) lK/1     <- inside the arm
#     d      <$> const[IV 5]           the RHS value
#     e  <@> print vK                  both sides converge here
#
# That refusal is correct as a backstop -- an arm that stops early would
# silently drop everything after the if/else -- but the construct it was
# refusing is one the walker already knows how to build.
#
# This is what blocks perl's own t/base/num.t and t/base/rs.t, which spell
# platform checks as `$a eq "0.01" || $a eq "1e-02" ? ... : ...` inside an
# `if ($^O eq ...) {...} else {...}`. Both files GAPped on this one shape.
subtest 'a value-context || inside an if/else arm lowers' => sub {
    my $g = graph_of('sub { my $a=1; if ($^O eq "os2") { print $a || 5 } else { print "b" } }');
    ok($g, 'the graph exists') or return;
    ok(scalar(ops_of($g, 'Or')), 'the || builds an Or node');
};

subtest 'a value-context && inside an if/else arm lowers' => sub {
    my $g = graph_of('sub { my $a=1; if ($^O eq "os2") { print $a && 5 } else { print "b" } }');
    ok(scalar(ops_of($g, 'And')), 'the && builds an And node');
};

# THE num.t SHAPE ITSELF: the short-circuit feeds a ternary condition.
subtest 'a || feeding a ternary inside an arm lowers' => sub {
    my $g = graph_of(
        'sub { my $a=0.01; if ($^O eq "os2") { print $a eq "0.01" || $a eq "1e-02" ? "y" : "n" }'
      . ' else { print "b" } }');
    ok(scalar(ops_of($g, 'Or')), 'the || builds an Or node');
};

# THE SAME VALUE THE MAIN WALK BUILDS. An arm is not a special case: the node
# built inside an arm must be the one built at the top level, or the arm path
# has invented a second lowering for one operator.
subtest 'the arm builds the same node the top level does' => sub {
    my $top = graph_of('sub { my $a=1; print $a || 5 }');
    my $arm = graph_of('sub { my $a=1; if ($^O eq "os2") { print $a || 5 } else { print "b" } }');
    is(scalar(ops_of($top, 'Or')), 1, 'the top-level form builds one Or');
    is(scalar(ops_of($arm, 'Or')), 1, 'the arm form builds one Or too');
};

# THE BACKSTOP MUST SURVIVE. The arm-did-not-reach-the-join refusal exists
# because an arm that stops early silently drops everything after the if/else.
# Handling and/or must not turn that into a pass-through for other unhandled
# ops -- a genuinely untranslatable arm still GAPs.
subtest 'a genuinely untranslatable arm still refuses' => sub {
    my $err = dies {
        graph_of('sub { if ($^O eq "os2") { my $s = eval "1+1"; print $s }'
               . ' else { print "b" } }')
    };
    like($err, qr/GAP/, 'an arm the walker cannot translate still dies with a GAP');
};

done_testing;
