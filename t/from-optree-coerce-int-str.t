# ABOUTME: A non-Str operand of an interpolation Concat is wrapped in a Stringify
# ABOUTME: (Int->Str coercion) for BOTH foldable and dynamic operands (zhi I6/R1b).

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# In Chalk "ok $n" is COERCION, not interpolation: the non-Str operand $n is
# stringified before the Concat. The multiconcat decoder must wrap any operand
# whose stamp is not already Str in a Stringify node, so the Concat sees only
# Str inputs. This holds for a FOLDABLE operand (my $n = 3, an Int Constant) and
# a DYNAMIC one (shift, a Call) alike -- neither may enter Concat raw.

sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

# Find every Concat node and report, for each, whether all its inputs are Str.
sub concat_input_reprs ($graph) {
    my @rows;
    for my $n ($graph->nodes->@*) {
        next unless $n->operation eq 'Concat';
        my @in = map {
            my $t = $_->can('stamp') && $_->stamp ? ($_->stamp->type // '?') : '?';
            { op => $_->operation, type => $t };
        } ($n->inputs // [])->@*;
        push @rows, \@in;
    }
    return \@rows;
}

sub has_raw_int_into_concat ($graph) {
    for my $row (concat_input_reprs($graph)->@*) {
        for my $in ($row->@*) {
            # A raw Int-stamped operand entering Concat: the coercion is missing.
            return 1 if $in->{type} eq 'Int';
        }
    }
    return 0;
}

sub has_stringify_input ($graph) {
    for my $row (concat_input_reprs($graph)->@*) {
        for my $in ($row->@*) {
            return 1 if $in->{op} eq 'Stringify';
        }
    }
    return 0;
}

subtest 'foldable operand: my $n = 3; "ok $n" wraps the Int in Stringify' => sub {
    my $g = translate(q{sub { my $n = 3; my $s = "ok $n"; $s }});
    ok(defined $g, 'translates (no GAP)');
    ok(has_stringify_input($g), 'Concat has a Stringify-wrapped operand');
    ok(!has_raw_int_into_concat($g), 'no raw Int enters Concat');
};

subtest 'dynamic operand: my $n = shift; "ok $n" wraps the value in Stringify' => sub {
    my $g = translate(q{sub { my $n = shift; my $s = "ok $n"; $s }});
    ok(defined $g, 'translates (no GAP)');
    ok(has_stringify_input($g), 'Concat has a Stringify-wrapped operand');
};

done_testing();
