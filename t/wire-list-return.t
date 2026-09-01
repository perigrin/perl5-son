# ABOUTME: A multi-value list return carries all N values on the wire, plus the
# ABOUTME: scalar reading (its LAST OPERAND) so a caller can pick by context.

use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub run_and_translate ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $out  = qx{$PERL $file 2>/dev/null};
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err" or return ''; local $/; <$e> } // '';
    return ( $out, ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub nodes_of ( $w, $method ) {
    return ( $w->{methods}{$method}{nodes} // [] );
}

# THE CALLEE IS COMPILED ONCE AND CANNOT SEE ITS CALLER'S CONTEXT, so it must
# emit BOTH readings and let the callsite pick. Measured semantics (pinned
# against perl in t/from-optree-list-return-gap.t):
#
#     return (10,20,30)               list -> 10,20,30    scalar -> 30
#     return @a         (3 elements)  list -> 1,2,3       scalar -> 3
#     my @x=(10,20); return (99,@x)   list -> 99,10,20    scalar -> 2
#
# The scalar reading is the LAST OPERAND read in scalar context, which is why
# it must be computed from the operand list BEFORE flattening.

subtest 'a literal list return carries every value' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'sub f { return (10,20,30) } my @l = f(); print "@l";', 'lit-list' );
    is $out, '10 20 30', 'perl yields all three' or return;
    ok $w, 'it translates rather than GAPping' or do { diag($err); return };

    my $ns = nodes_of( $w, 'main::f' );
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($ret) = grep { ( $_->{op} // '' ) eq 'Return' } $ns->@*;
    ok $ret, 'the callee has a Return' or return;

    my $v = $by{ ( $ret->{inputs} // [] )->[0] // '' };
    ok $v, 'it returns a value' or return;
    is scalar( ( $v->{inputs} // [] )->@* ), 3,
        'the returned value carries all three values, not one';
};

subtest 'a scalar-context callsite reads the last operand' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'sub f { return (10,20,30) } my $s = f(); print $s;', 'lit-scalar' );
    is $out, '30', 'perl yields the last operand' or return;
    ok $w, 'it translates' or do { diag($err); return };

    # The caller must not receive the whole container: that was the miscompile
    # in the reverted attempt, where Print read Call(:Array) and printed it.
    my $ns = nodes_of( $w, 'main::__PROGRAM__' );
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($print) = grep { ( $_->{op} // '' ) eq 'Print' } $ns->@*;
    ok $print, 'the program prints something' or return;

    my $v = $by{ ( $print->{inputs} // [] )->[0] // '' };
    $v = $by{ ( $v->{inputs} // [] )->[0] // '' }
        while $v && ( $v->{op} // '' ) eq 'Coerce';
    ok $v, 'the printed value resolves' or return;
    isnt $v->{stamp}, 'Array',
        'the printed value is not the raw container';

    # THE CALLEE MUST BE PRESENT. B::SoN emits the caller even when it skips
    # the callee, so a test that only inspects the program passes while the
    # feature is entirely missing -- the vacuous-pass trap.
    ok scalar( nodes_of( $w, 'main::f' )->@* ),
        'the callee graph is emitted, not skipped';

    # The callsite must say which reading it wants; without that the callee's
    # two readings cannot be chosen between.
    my ($call) = grep { ( $_->{op} // '' ) eq 'Call' } $ns->@*;
    ok $call, 'the program calls f' or return;
    is $call->{fields}{want}, 'scalar',
        'the Call records its callsite context';
};

# THE CASE THAT KILLED elements[len-1]: a trailing AGGREGATE operand yields its
# LENGTH, not its last element. Any collapse computed after flattening gets 20
# here; perl says 2.
subtest 'a trailing aggregate operand yields its length' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'sub f { my @x=(10,20); return (99,@x) } my $s = f(); print $s;',
        'trailing-agg' );
    is $out, '2', 'perl yields the array length, not its last element' or return;
    ok $w, 'it translates' or do { diag($err); return };

    my $ns = nodes_of( $w, 'main::__PROGRAM__' );
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($print) = grep { ( $_->{op} // '' ) eq 'Print' } $ns->@*;
    ok $print, 'the program prints something' or return;

    # A Count must appear -- but WHICH node it counts is the whole rule, and
    # asserting only its existence passes on the wrong one. `return (98,99,@x)`
    # with a 2-element @x is 2, while the outer operand list has 3 members, so
    # a Count of the LIST is wrong wherever those numbers differ.
    my $fns = nodes_of( $w, 'main::f' );
    my %fby = map { $_->{id} => $_ } $fns->@*;
    my ($count) = grep { ( $_->{op} // '' ) eq 'Count' } $fns->@*;
    ok $count, 'a Count computes the trailing aggregate length' or return;

    my $counted = $fby{ ( $count->{inputs} // [] )->[0] // '' };
    ok $counted, 'the Count has an operand' or return;
    is scalar( ( $counted->{inputs} // [] )->@* ), 2,
        'it counts the TRAILING ARRAY (2), not the operand list';
};

# THE DISCRIMINATING CASE for that rule: leading operand count and trailing
# array length differ, so a Count of the wrong node gives a different answer.
subtest 'the scalar reading counts the last operand, not the list' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'sub f { my @x=(10,20); return (98,99,@x) } my $s = f(); print $s;',
        'count-discriminating' );
    is $out, '2', 'perl yields the trailing array length (2), not 3' or return;
    ok $w, 'it translates' or do { diag($err); return };

    my $fns = nodes_of( $w, 'main::f' );
    my %fby = map { $_->{id} => $_ } $fns->@*;
    my ($count) = grep { ( $_->{op} // '' ) eq 'Count' } $fns->@*;
    ok $count, 'a Count exists' or return;
    my $counted = $fby{ ( $count->{inputs} // [] )->[0] // '' };
    is scalar( ( $counted->{inputs} // [] )->@* ), 2,
        'the counted node has two elements, matching @x not the operand list';
};

subtest 'a list-context callsite still receives every value' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'sub f { my @x=(10,20); return (99,@x) } my @l = f(); print scalar(@l);',
        'trailing-agg-list' );
    is $out, '3', 'perl flattens to three values' or return;
    ok $w, 'it translates' or diag($err);
    return unless $w;
    my $ns = nodes_of( $w, 'main::f' );
    ok scalar($ns->@*), 'the callee graph is present';
};

# THE SCALAR READING MUST BE REACHABLE BY CONTRACT, not by accident.
#
# It was first emitted as a free-floating Coerce that nothing consumed. It
# survived serialization only because graph membership is BIDIRECTIONAL
# reachability -- the Coerce reaches back to its operand -- so it rode along
# without any node pointing at it. That is not a contract: a consumer has no
# defined place to look for it, and any dead-code pass would delete it, taking
# the scalar reading with it and leaving a graph that looks complete.
#
# It now rides on the Return as inputs[1], so the node that carries the list
# reading also carries the scalar one.
subtest 'the scalar reading rides on the Return, not free-floating' => sub {
    for my $case (
        [ 'sub f { return (10,20,30) } my $s=f(); print $s;', 'lit' ],
        [ 'sub f { my @x=(10,20); return (99,@x) } my $s=f(); print $s;', 'mix' ],
    ) {
        my ( $src, $label ) = $case->@*;
        my ( undef, $w, $err ) = run_and_translate( $src, "reachable-$label" );
        ok $w, "it translates ($label)" or do { diag($err); next };

        my $ns = nodes_of( $w, 'main::f' );
        my %by = map { $_->{id} => $_ } $ns->@*;
        my ($ret) = grep { ( $_->{op} // '' ) eq 'Return' } $ns->@*;
        ok $ret, "the callee has a Return ($label)" or next;

        my @in = ( $ret->{inputs} // [] )->@*;
        is scalar(@in), 2,
            "the Return carries both readings ($label)";

        my $scalar_face = $by{ $in[1] // '' };
        ok $scalar_face, "the second input resolves ($label)" or next;
        is $scalar_face->{op}, 'Coerce',
            "... and it is the scalar-face Coerce ($label)";

        # Nothing may be left unconsumed: an orphan is exactly the shape this
        # subtest exists to forbid.
        my %consumed;
        for my $n ( $ns->@* ) { $consumed{$_} = 1 for ( $n->{inputs} // [] )->@* }
        my @orphans = grep {
            my $id = $_->{id};
            ( $_->{op} // '' ) eq 'Coerce' && !$consumed{$id}
        } $ns->@*;
        is scalar(@orphans), 0, "no dangling Coerce remains ($label)";
    }
};

# THE SUB'S DECLARED RETURN TYPE IS THE LIST READING, inputs[0]. Adding a
# second Return input silently changed this: _graph_return_type read
# `inputs->[-1]`, which was the value while a Return had exactly one input and
# became the SCALAR FACE the moment there were two. The Call's stamp flipped
# from List to Scalar with no test failing, because nothing asserted it.
subtest 'a list-returning sub is stamped by its list reading' => sub {
    my ( undef, $w, $err ) = run_and_translate(
        'sub f { return (10,20,30) } my @l = f(); print scalar(@l);',
        'return-type' );
    ok $w, 'it translates' or do { diag($err); return };

    my $ns = nodes_of( $w, 'main::__PROGRAM__' );
    my ($call) = grep {
        ( $_->{op} // '' ) eq 'Call'
            && ( $_->{fields}{name} // '' ) eq 'main::f'
    } $ns->@*;
    ok $call, 'the program calls f' or return;

    is $call->{stamp}, 'List',
        'the Call is stamped by the LIST reading, not the scalar face';
};

# THE RETURN CONTRACT, pinned at the node level. Consumers reached for
# `inputs->[-1]` -- correct while a Return had exactly one input and silently
# the scalar face once it had two. That assumption cost one bug here and three
# live sites in chalk, so both slots now have names and both are asserted.
subtest 'Return exposes both readings by name' => sub {
    use SoN::FromOptree;

    my $multi = eval 'sub { return (10,20,30) }';
    my $graph = SoN::FromOptree->translate($multi);
    my ($ret) = grep { $_->operation eq 'Return' } $graph->nodes->@*;
    ok $ret, 'a multi-value return has a Return' or return;

    is $ret->value->operation, 'ArrayLiteral',
        'value() is the list reading';
    ok defined $ret->scalar_value,
        'scalar_value() is present for a multi-value return';
    is $ret->scalar_value->operation, 'Coerce',
        '... and it is the scalar-face Coerce';

    # A SINGLE-VALUE RETURN HAS NO SECOND FACE. value() and inputs[-1] agree
    # here, which is exactly why the bug hid: every pre-existing shape made
    # the two indistinguishable.
    my $single = eval 'sub { return 42 }';
    my $g2 = SoN::FromOptree->translate($single);
    my ($r2) = grep { $_->operation eq 'Return' } $g2->nodes->@*;
    ok $r2, 'a single-value return has a Return' or return;
    ok defined $r2->value, 'value() is present';
    ok !defined $r2->scalar_value,
        'scalar_value() is absent -- there is no second reading to take';
};

# THE LIST READING IS FLATTENED, not nested. `return (99,@x)` in list context
# yields THREE values, and perl agrees for both a static and a runtime @x:
#
#     my @x=(10,20);      return (99,@x)  -> 99 10 20   (3)
#     my @x=(1..$n);      return (99,@x)  -> 99 1 2 3   (4 for $n=3)
#
# Emitting ArrayLiteral[99, ArrayLiteral[10,20]] makes a consumer counting
# inputs read 2 where perl says 3, and forces it to box a nested aggregate --
# which chalk cannot tag honestly, since an %Array* is not a boxed pointer to
# an %Array. Every list return B::SoN emits has STATIC arity (a runtime range
# refuses upstream), so the flattening is always possible here.
subtest 'a list return flattens its aggregate operands' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'sub mix { my @x=(10,20); return (99,@x) } my @l = mix(); print scalar(@l);',
        'flatten' );
    is $out, '3', 'perl yields three values' or return;
    ok $w, 'it translates' or do { diag($err); return };

    my $ns = nodes_of( $w, 'main::mix' );
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($ret) = grep { ( $_->{op} // '' ) eq 'Return' } $ns->@*;
    ok $ret, 'the callee has a Return' or return;

    my $list = $by{ ( $ret->{inputs} // [] )->[0] // '' };
    ok $list, 'it returns a list value' or return;
    is scalar( ( $list->{inputs} // [] )->@* ), 3,
        'the list reading holds three values, not two-with-a-nested-array';

    # No input may itself be an aggregate: that is the nesting, restated.
    my @nested = grep {
        my $in = $by{$_};
        $in && ( $in->{stamp} // '' ) =~ /\A(?:Array|Hash|List)\z/
    } ( $list->{inputs} // [] )->@*;
    is scalar(@nested), 0, 'and none of them is itself an aggregate';

    # The SCALAR reading must survive the flattening: `return (99,@x)` in
    # scalar context is @x's LENGTH (2), not its last element and not 3.
    my ($count) = grep { ( $_->{op} // '' ) eq 'Count' } $ns->@*;
    ok $count, 'a Count still computes the scalar reading' or return;
    my $counted = $by{ ( $count->{inputs} // [] )->[0] // '' };
    is scalar( ( $counted->{inputs} // [] )->@* ), 2,
        '... over the trailing array (2), not the flattened list';
};

done_testing;
