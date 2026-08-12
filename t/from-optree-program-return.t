# ABOUTME: A PROGRAM has no return value; its Return must not adopt stack residue.
# ABOUTME: A sub's Return still carries its last statement's value.

use v5.42.0;
use Test2::V0;
use JSON::PP;

# Translate SOURCE as a whole program (the main_root walk translate_root does)
# and return { graph_name => { id => node } } plus the Return node per graph.
sub program_graphs ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;

    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;

    my $data = eval { JSON::PP->new->decode($out) }
        or return undef;
    return $data->{methods};
}

# ($return_node, \%by_id) for one graph, or () when absent.
sub return_of ($methods, $name) {
    my $g = $methods->{$name} or return ();
    my %by_id = map { $_->{id} => $_ } $g->{nodes}->@*;
    my ($ret) = grep { ($_->{op} // '') eq 'Return' } $g->{nodes}->@*;
    return ($ret, \%by_id);
}

# A program's top level runs every statement in VOID context, so nothing is
# legitimately left on the simulated stack at exit. `_exit_record` takes
# `$sim->pop_node` -- right for a sub, whose last statement leaves its value
# there -- so a program's Return adopts whatever residue an earlier statement
# left behind.
#
# Measured before the fix:
#   my @a = (1,2,3); say(scalar @a);            Return <- ArrayRef    (from `my @a`)
#   my $n=5; my $x=0; $x = 1 if $n>0; say($x);  Return <- Constant(0) (from `my $x = 0`)
#
# Perl is unambiguous that there is no value: the trailing statement compiles in
# void context (`padsv ... v`, `leave ... vKP`) and the last value has no effect
# on exit status. The honest Return value is Undef.
subtest 'a program Return does not adopt an earlier statement value' => sub {
    my $methods = program_graphs(<<'SRC');
use 5.42.0;
my @a = (1, 2, 3);
say(scalar @a);
SRC
    ok($methods, 'decoded the producer JSON') or return;

    my ($ret, $by_id) = return_of($methods, 'main::__PROGRAM__');
    ok($ret, 'found the program Return') or return;

    my $input = $by_id->{ $ret->{inputs}[0] };
    ok($input, 'the Return has an input node') or return;

    isnt($input->{op}, 'ArrayRef',
        'the Return does not consume the array built by an earlier statement');
    is($input->{op}, 'Constant', 'the Return consumes a Constant');
    is($input->{fields}{const_type}, 'undef', 'and that Constant is the Undef');
};

subtest 'the residue case with TWO stale values' => sub {
    my $methods = program_graphs(<<'SRC');
use 5.42.0;
my $n = 5;
my $x = 0;
$x = 1 if $n > 0;
say($x);
SRC
    ok($methods, 'decoded the producer JSON') or return;

    my ($ret, $by_id) = return_of($methods, 'main::__PROGRAM__');
    ok($ret, 'found the program Return') or return;

    # The pre-fix wiring took Constant(0) -- `my $x = 0`'s initializer. The
    # post-fix value is ALSO a Constant, so the op alone cannot discriminate:
    # assert the const_type.
    my $input = $by_id->{ $ret->{inputs}[0] };
    ok($input, 'the Return has an input node') or return;
    is($input->{fields}{const_type}, 'undef',
        'the Return value is Undef, not `my $x = 0`\'s integer initializer');
};

# The BILATERAL partner. A SUB's return value is real and must be untouched by
# the program-exit change -- without this, "return Undef at every exit" would
# pass the cases above while silently breaking every sub in the corpus.
subtest 'a SUB still returns its last statement value' => sub {
    # NOT `6 * 7` -- perl's constant folder computes that at compile time and
    # the Return consumes a plain Constant, which cannot be told apart from the
    # Undef this change introduces. The body must be genuinely runtime-computed.
    my $methods = program_graphs(<<'SRC');
use 5.42.0;
sub f { my $x = shift; $x * 2 }
say f(21);
SRC
    ok($methods, 'decoded the producer JSON') or return;

    my ($ret, $by_id) = return_of($methods, 'main::f');
    ok($ret, 'found the sub Return') or return;

    my $input = $by_id->{ $ret->{inputs}[0] };
    ok($input, 'the sub Return has an input node') or return;
    is($input->{op}, 'Multiply', 'the sub Return consumes its computed value');
};

done_testing;
