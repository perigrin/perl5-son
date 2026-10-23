# ABOUTME: Tests a flat if/else where BOTH arms store an element builds one If, two guarded Projs, one Region + memory-Phi (2b-3).
# ABOUTME: Each store is control-dependent on its own Proj(If); the post-branch read's memory is a Phi over the Region with TWO store inputs.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN;
use SoN::FromOptree;
use SoN::Deparse;
use JSON::PP;
use File::Temp qw(tempdir);

# `if ($c) { $a[0] = 7 } else { $a[0] = 8 } $a[0]` -- BOTH arms store to the
# same element. Each store is CONTROL-DEPENDENT on its own arm's Proj(If); the
# merge Region is over [true_arm_control, false_arm_control] and the memory
# after the join is a Phi with TWO real store inputs. This is the flat
# both-arms-store shape (2b-3), NOT a memory value-select TernaryExpr.

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub of_op ($g, $op) { grep { $_->operation eq $op } $g->nodes->@* }

my $SRC = 'sub { my @a = (1,2,3); my $c = 1; if ($c) { $a[0] = 7 } else { $a[0] = 8 } $a[0] }';

subtest 'the if/else builds exactly one If + one Region' => sub {
    my $g = graph_of($SRC);
    is(scalar(of_op($g, 'If')), 1, 'exactly one If node');
    is(scalar(of_op($g, 'Region')), 1, 'exactly one Region (the join)');
};

subtest 'both element stores are control-dependent on distinct Projs of the If' => sub {
    my $g = graph_of($SRC);
    my @stores = grep {
        grep { ref $_ && $_->operation eq 'Subscript' } $_->inputs->@*
    } of_op($g, 'Assign');
    is(scalar(@stores), 2, 'two element-store Assigns') or return;
    my ($if) = of_op($g, 'If');
    my %proj_index;
    for my $store (@stores) {
        my $ctrl = $store->can('control_in') ? $store->control_in : undef;
        ok(defined $ctrl, 'store has a control input') or next;
        is($ctrl->operation, 'Proj', 'store control is a Proj');
        is($ctrl->inputs->[0], $if, 'the Proj is off the one If');
        $proj_index{$ctrl->index}++;
    }
    is([sort keys %proj_index], [0, 1],
        'the two stores are on distinct Projs (index 0 true arm, index 1 false arm)');
};

subtest 'the post-branch read memory is a Phi over the Region with two store inputs' => sub {
    my $g = graph_of($SRC);
    my ($ret) = of_op($g, 'Return');
    my $read = $ret->inputs->[-1];
    is($read->operation, 'Subscript', 'the return value is a Subscript (the read)') or return;
    my $mem = $read->inputs->[2];
    ok(defined $mem, 'the read has a memory input') or return;
    is($mem->operation, 'Phi', 'the read memory is a Phi (the memory merge)') or return;
    ok(defined $mem->region && $mem->region->operation eq 'Region',
        'the Phi is over the Region');
    is(scalar($mem->inputs->@*), 2, 'the memory-Phi has two inputs');
    # Both inputs are real stores (element-store Assigns), one per arm -- NOT
    # a base-memory passthrough. Each input carries a Subscript lvalue.
    my $both_stores = 0;
    for my $in ($mem->inputs->@*) {
        $both_stores++ if $in->operation eq 'Assign'
            && grep { ref $_ && $_->operation eq 'Subscript' } $in->inputs->@*;
    }
    is($both_stores, 2, 'both memory-Phi inputs are element stores (one per arm)');
    # Exactly one Phi: the memory merge, no spurious stack Phi from the
    # discarded stored value.
    is(scalar(of_op($g, 'Phi')), 1, 'exactly one Phi (the memory merge, no stack Phi)');
};

subtest 'a VALUE-context ternary whose arms store an element merges the stored value' => sub {
    # `my $x = $c ? ($a[0]=7) : ($a[0]=8); $x` -- each arm's element-store
    # assign leaves its value on the stack, so the arms merge into a value Phi
    # at the join beside the memory-Phi. The program must print what perl does.
    my $src = 'my @a = (1,2,3); for my $c (1, 0) { my $x = $c ? ($a[0]=7) : ($a[0]=8); print "$x @a\n" }';
    my $dir = tempdir(CLEANUP => 1);
    my $f = "$dir/p.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $want = qx($^X $f);
    my $json = qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err);
    my $out = SoN::Deparse->new->render(JSON::PP->new->decode($json));
    ok(defined $out, 'the graph renders');
    open $fh, '>', "$dir/o.pl" or die $!; print $fh $out // ''; close $fh;
    is(scalar qx($^X $dir/o.pl), $want, 'and prints what perl prints');
};

done_testing();
