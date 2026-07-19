# ABOUTME: Tests SoN::FromOptree array/hash construction and element writes.
# ABOUTME: Canonical (suppressed) ops: aassign->ArrayRef/HashRef, aelem/helem store + read.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;
use SoN::FromOptree::EffectMeta;

# Under canonical (peephole-suppressed) ops, `my @a = (...)` builds an ArrayRef
# bound to the array, `$a[0] = V` is a threaded stmt-effect Assign store, and a
# later `$a[0]` is a real Subscript LOAD (not a compile-time value substitution),
# so the store persists to memory and the load sees it. Same for hashes.

sub canonical_graph ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub return_value_node ($graph) {
    my ($ret) = grep { $_->operation eq 'Return' } $graph->nodes->@*;
    return $ret->inputs->[-1];
}

subtest 'array construction builds an ArrayRef' => sub {
    my $g = canonical_graph('sub { my @a = (1,2,3); $a[0] }');
    my @ops = map { $_->operation } $g->nodes->@*;
    ok((grep { $_ eq 'ArrayRef' } @ops), 'has an ArrayRef for my @a = (1,2,3)');
};

subtest 'array element read returns the constructed element' => sub {
    my $g = canonical_graph('sub { my @a = (10,20,30); $a[1] }');
    my $val = return_value_node($g);
    is($val->operation, 'Subscript', 'read is a Subscript');
};

subtest 'array element store is a threaded Assign; read is a real Subscript load' => sub {
    # The store materialises: a stmt-effect Assign on the control chain, and the
    # read is a real Subscript LOAD (not the stored Constant substituted in), so
    # the store persists to memory and the load sees it (correct under aliasing).
    my $g = canonical_graph('sub { my @a = (1,2,3); $a[0] = 42; $a[0] }');
    my $val = return_value_node($g);
    is($val->operation, 'Subscript', 'read is a Subscript load, not the stored Constant');

    my ($assign) = grep { $_->operation eq 'Assign' } $g->nodes->@*;
    ok(defined $assign, 'the store emits an Assign') or return;
    ok(SoN::FromOptree::EffectMeta::is_stmt_effect($assign),
        'the store Assign is a threaded stmt-effect');
};

subtest 'hash construction builds a HashRef' => sub {
    my $g = canonical_graph('sub { my %h = (k => 0); $h{k} }');
    my @ops = map { $_->operation } $g->nodes->@*;
    ok((grep { $_ eq 'HashRef' } @ops), 'has a HashRef for my %h = (k => 0)');
};

subtest 'hash element store is a threaded Assign; read is a real Subscript load' => sub {
    my $g = canonical_graph('sub { my %h = (k => 0); $h{k} = 99; $h{k} }');
    my $val = return_value_node($g);
    is($val->operation, 'Subscript', 'read is a Subscript load, not the stored Constant');

    my ($assign) = grep { $_->operation eq 'Assign' } $g->nodes->@*;
    ok(defined $assign && SoN::FromOptree::EffectMeta::is_stmt_effect($assign),
        'the store is a threaded stmt-effect Assign');
};

done_testing();
