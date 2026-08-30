# ABOUTME: An else-less `if` inside a loop body is a guarded statement, not a
# ABOUTME: loop condition -- it must build a real If, not silently vanish.
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

# THE GAP, and why it is narrow. Perl compiles an else-less `if` to an `and` op
# -- the SAME shape as a postfix modifier and as the loop's own iteration guard:
#
#     l  <|> and(other->7)      <- the iterator's `and` (the loop condition)
#     b  <|> and(other->c)      <- `if ($i<1) { print "a" }`  THE GUARD
#     c      ... print "a"          the guard-taken arm
#     f  <;> nextstate              the rest of the body (guard-not-taken falls here)
#
# The walker's condition handler would treat that second `and` as the loop
# condition, drop the guard's If, and run the guarded statement EVERY iteration.
# That is a silent miscompile, not a crash: `$s=$s+$i unless $i==2` over 1..3
# gave 106 instead of 104. So the walker GAPped instead -- correctly refusing
# rather than lying.
#
# The refusal was much broader than the miscompile. An `if/else` in a loop body
# ALREADY worked (perl builds a cond_expr, which the walker handles); only the
# ELSE-LESS form failed, because only that form compiles to an `and`. One branch
# shape, not conditionals in general.
subtest 'an else-less if in a foreach body builds a real If' => sub {
    my $g = graph_of('sub { my $s=0; for my $i (0..3) { if ($i != 2) { $s = $s + $i; } } $s }');
    ok($g, 'the graph exists') or return;
    ok(scalar(ops_of($g, 'Loop')), 'the loop is built');
    ok(scalar(ops_of($g, 'If')), 'the guard builds an If -- it did not vanish');
};

# THE POSTFIX FORM is the same optree shape and must lower the same way.
subtest 'a postfix modifier in a foreach body builds a real If' => sub {
    my $g = graph_of('sub { my $s=0; for my $i (0..3) { $s = $s + $i if $i != 2; } $s }');
    ok(scalar(ops_of($g, 'If')), 'the modifier guard builds an If');
};

# THE WHILE TWIN. Same shape, same handler, different loop builder.
subtest 'an else-less if in a while body builds a real If' => sub {
    my $g = graph_of('sub { my $s=0; my $t=0; while ($t<3) { $t=$t+1; $s=$s+1 if $t!=2; } $s }');
    ok(scalar(ops_of($g, 'Loop')), 'the loop is built');
    ok(scalar(ops_of($g, 'If')), 'the guard builds an If');
};

# THE ACCUMULATOR MUST PHI. This is the assertion that would have caught the
# original miscompile: if the guard were dropped, the guarded add would run
# unconditionally and there would be no merge Phi joining "added" with
# "skipped". A loop-carried slot written on ONE arm has to merge.
subtest 'a slot written only on the guarded arm merges' => sub {
    my $g = graph_of('sub { my $s=0; for my $i (0..3) { if ($i != 2) { $s = $s + $i; } } $s }');
    my @phis = ops_of($g, 'Phi');
    ok(scalar(@phis) >= 2,
        'both the loop-carried Phi and the guard merge Phi exist')
        or diag("only " . scalar(@phis) . " Phi(s)");
};

# WHAT ALREADY WORKED stays working -- the if/else form was never the problem,
# and a regression here would mean the fix broke the cond_expr path.
subtest 'if/else in a loop body is unaffected' => sub {
    my $g = graph_of('sub { my $s=0; for my $i (0..3) { if ($i<2) { $s=$s+1 } else { $s=$s+10 } } $s }');
    ok(scalar(ops_of($g, 'Loop')), 'the loop is built');
};

done_testing;
