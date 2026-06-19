# ABOUTME: Tests SoN::FromOptree against canonical (peephole-suppressed) optrees.
# ABOUTME: The -MO=SoN flow suppresses rpeep, so element/var ops arrive unfused.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# The real producer flow (-MO=SoN) suppresses the peephole optimizer so element
# access, list intro, and scalar assignment arrive in canonical, unfused form
# (aelem/helem/sassign/padsv rather than aelemfast/multideref/padrange). These
# tests compile the target subs WITH suppression active, exercising exactly the
# path B::SoN uses, which the fused-path unit tests do not cover.

sub canonical_translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub ops_of ($graph) { [ map { $_->operation } $graph->nodes->@* ] }

subtest 'variable passthrough binds to the value (not a bare PadAccess)' => sub {
    my $g = canonical_translate('sub { my $x = 1; $x }');
    my @ops = ops_of($g)->@*;
    # The returned value must be the Constant, not an unstamped PadAccess.
    ok((grep { $_ eq 'Constant' } @ops), 'has the bound Constant');
    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    is($ret->inputs->[-1]->operation, 'Constant',
        'return value is the bound Constant (canonical sassign rebind worked)');
};

subtest 'reassignment rebinds to the new value' => sub {
    my $g = canonical_translate('sub { my $x = 1; $x = 2; $x }');
    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    my $val = $ret->inputs->[-1];
    is($val->operation, 'Constant', 'return value is a Constant');
    is($val->value, 2, 'reassignment took effect: value is 2, not 1');
};

subtest 'canonical element read produces Subscript(array, index)' => sub {
    my $g = canonical_translate('sub { my @a = (1,2,3); $a[0] }');
    my @ops = ops_of($g)->@*;
    ok((grep { $_ eq 'Subscript' } @ops),
        'element read is a Subscript (canonical aelem, not opaque aelemfast)');
};

done_testing();
