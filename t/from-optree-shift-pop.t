# ABOUTME: Tests shift/pop lowering: the removed value is stamped with the array
# ABOUTME: element type and the mutation threads through memory-SSA (is_stmt_effect).

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;
use SoN::FromOptree::EffectMeta;

sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub nodes_by_op ($graph, $op) {
    return grep { $_->operation eq $op } $graph->nodes->@*;
}

subtest 'shift @arr is a memory statement effect stamped with the element type' => sub {
    my $g = translate('sub { my @q = (1, 2, 3); my $x = shift @q; $x }');
    my ($shift) = grep { ($_->name // '') eq 'shift' } nodes_by_op($g, 'Call');
    ok($shift, 'a shift Call node exists');
    ok(SoN::FromOptree::EffectMeta::is_stmt_effect($shift),
        'shift is a statement effect (memory mutation)');
    ok(defined $shift->stamp, 'shift result is stamped');
    is($shift->stamp->type, 'Int', 'shift of an Int array yields an Int');
    # inputs = [control, array, memory]; the array is the aggregate input.
    my ($arr) = grep {
        my $r = $_->stamp ? $_->stamp->type : '';
        $_->operation eq 'ArrayRef'
    } $shift->inputs->@*;
    ok($arr, 'the array is an input to the shift Call');
};

subtest 'pop @arr is likewise a stamped memory effect' => sub {
    my $g = translate('sub { my @q = (5, 6); my $x = pop @q; $x }');
    my ($pop) = grep { ($_->name // '') eq 'pop' } nodes_by_op($g, 'Call');
    ok($pop, 'a pop Call node exists');
    ok(SoN::FromOptree::EffectMeta::is_stmt_effect($pop), 'pop is a statement effect');
    is($pop->stamp->type, 'Int', 'pop of an Int array yields an Int');
};

subtest 'bare shift (from @_) is not treated as an array drain' => sub {
    # Bare `shift` reads @_, not a lexical array literal -- it must NOT take the
    # element-stamp / memory-effect path (its operand is not an aggregate node).
    my $g = translate('sub { my $x = shift; $x }');
    my ($shift) = grep { ($_->name // '') eq 'shift' } nodes_by_op($g, 'Call');
    ok($shift, 'a bare shift Call node exists');
    ok(!SoN::FromOptree::EffectMeta::is_stmt_effect($shift),
        'bare shift is NOT the array-drain memory effect');
};

done_testing;
