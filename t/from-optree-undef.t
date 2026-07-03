# ABOUTME: Tests SoN::FromOptree translates the undef op (my $a = undef; bare undef).
# ABOUTME: TARGMY undef binds the pad slot to an Undef Constant; corpus logical.md L3b.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# Per corpus/mdtest/logical.md L3b, `my $a = undef; $a // $b` is DefinedOr
# whose LEFT operand is the Undef constant $a was bound to. Perl compiles
# `my $a = undef` to a single undef op with LVINTRO+TARGMY (the sassign is
# nulled), so the producer must bind the targ itself.

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

subtest 'my $a = undef binds the slot to an Undef Constant (L3b)' => sub {
    my $g = graph_of('sub { my $a = undef; my $b = 7; $a // $b }');
    my ($dor) = grep { $_->operation eq 'DefinedOr' } $g->nodes->@*;
    ok(defined $dor, 'has a DefinedOr node') or return;
    my $lhs = $dor->inputs->[0];
    is($lhs->operation, 'Constant', 'lhs is a Constant');
    is($lhs->const_type, 'undef', 'lhs is the undef constant');
    is($dor->inputs->[1]->value, 7, 'rhs is the $b binding');
};

subtest 'a later read of the undef-initialized lexical sees the binding' => sub {
    my $g = graph_of('sub { my $a = undef; $a }');
    my $ret = $g->returns->[0];
    my ($val) = grep { $_->operation eq 'Constant' } $ret->inputs->@*;
    ok(defined $val, 'return carries the bound value') or return;
    is($val->const_type, 'undef', 'reading $a returns the undef constant');
};

subtest 'bare undef as a value pushes an Undef Constant' => sub {
    my $g = graph_of('sub { return undef }');
    my $ret = $g->returns->[0];
    my ($val) = grep { $_->operation eq 'Constant' } $ret->inputs->@*;
    ok(defined $val, 'return carries a Constant') or return;
    is($val->const_type, 'undef', 'the constant is undef');
};

done_testing();
