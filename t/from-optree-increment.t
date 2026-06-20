# ABOUTME: Tests SoN::FromOptree pre/post increment and decrement (++ --).
# ABOUTME: Read-modify-write: pre yields the new value, post the old value.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# ++$i / --$i are read-modify-write on an lvalue pad (dedicated preinc/predec
# ops, NOT TARGMY): read $i, +/- 1, rebind $i. A PRE op yields the new value;
# a POST op ($i++) yields the old value. (Perl collapses a void-context $i++ to
# preinc, so a read-after sees the new value either way.)

sub canonical_graph ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub return_value ($graph) {
    my ($ret) = grep { $_->operation eq 'Return' } $graph->nodes->@*;
    return $ret->inputs->[-1];
}

subtest 'pre-increment rebinds; read-after returns the new value' => sub {
    my $rv = return_value(canonical_graph('sub { my $i = 0; ++$i; $i }'));
    is($rv->operation, 'Add', 'read after ++$i is the Add (new value)');
    is($rv->stamp->type, 'Int', 'increment result is stamped Int');
};

subtest 'pre-decrement uses Subtract' => sub {
    my $rv = return_value(canonical_graph('sub { my $i = 5; --$i; $i }'));
    is($rv->operation, 'Subtract', 'read after --$i is the Subtract');
};

subtest 'post-increment read-after returns the new value' => sub {
    my $rv = return_value(canonical_graph('sub { my $i = 0; $i++; $i }'));
    is($rv->operation, 'Add', 'read after $i++ is the new value (1)');
};

subtest 'post-increment expression yields the OLD value' => sub {
    # my $j = $i++ -> $j is the old value of $i (0), not the incremented one.
    my $rv = return_value(canonical_graph('sub { my $i = 0; my $j = $i++; $j }'));
    is($rv->operation, 'Constant', 'post-inc result is the old value');
    is($rv->value, 0, 'old value is 0');
};

subtest 'pre-increment expression yields the NEW value' => sub {
    my $rv = return_value(canonical_graph('sub { my $i = 0; my $j = ++$i; $j }'));
    is($rv->operation, 'Add', 'pre-inc result is the new value');
};

done_testing();
