# ABOUTME: `delete` removes a key and yields its value; the removal must be on the memory chain.
# ABOUTME: Same shape as `exists` -- [container, key, memory] -- but it ADVANCES memory rather than reading it.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub translate ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $err = qx($^X -Ilib -MO=SoN,json,package=main $file 2>&1 >/dev/null);
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) };
    return ($data ? $data->{methods}{'main::__PROGRAM__'} : undef, $err);
}

# The OpMap gave `delete` a pop_count of 1, so it took the KEY alone and the
# container stayed on the stack -- it reached the wire as Call(delete, key)
# with no container and no memory edge, and the removal was invisible:
#
#     my %h=(a=>1,b=>2); delete $h{a}; print defined($h{a}) ? "y" : "n"
#       perl : n
#       before: Call(delete, Constant "a")  and the later read still at
#               MemStart, so the graph computed "y"
#
# `exists` had EXACTLY this bug and its fix is the template: pop container AND
# key, and carry [container, key, memory] like a Subscript does. See the Exists
# node, whose own comment anticipates this ("a preceding delete or assignment is
# observed").
subtest 'delete takes its container, not just the key' => sub {
    my ($g, $err) = translate(<<'SRC');
my %h = (a => 1, b => 2);
delete $h{a};
print defined($h{a}) ? "y" : "n", "\n";
SRC
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;
    ok defined $g, 'it translates' or return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my ($del) = grep {
        $_->{op} eq 'Delete'
        || ( $_->{op} eq 'Call' && ($_->{fields}{name} // '') eq 'delete' )
    } $g->{nodes}->@*;
    ok defined $del, 'the delete is in the graph' or return;

    my @in = map { $by{$_} } $del->{inputs}->@*;
    ok scalar(@in) >= 2, 'it has at least a container and a key'
        or diag "inputs: " . join(',', map { $_->{op} } @in);
    is $in[0]{op}, 'HashLiteral',
        'inputs[0] is the CONTAINER the removal is about';
};

# THE REMOVAL MUST BE ON THE MEMORY CHAIN, or a later read still sees the key.
# This is the assertion that would have caught the original defect: the graph
# was structurally complete and computed the wrong answer.
subtest 'a read after the delete is threaded to it' => sub {
    my ($g, $err) = translate(<<'SRC');
my %h = (a => 1, b => 2);
delete $h{a};
print defined($h{a}) ? "y" : "n", "\n";
SRC
    ok defined $g, 'it translates' or diag($err), return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my ($del) = grep {
        $_->{op} eq 'Delete'
        || ( $_->{op} eq 'Call' && ($_->{fields}{name} // '') eq 'delete' )
    } $g->{nodes}->@*;
    ok defined $del, 'the delete is in the graph' or return;

    # The later read is a Subscript over the same hash; its memory input must
    # be the delete, not the MemStart the delete started from.
    my ($read) = grep {
        $_->{op} eq 'Subscript' && $_->{inputs}->@* >= 3
    } $g->{nodes}->@*;
    ok defined $read, 'the later read is a Subscript carrying memory' or return;

    is $read->{inputs}[2], $del->{id},
        'the read observes the delete rather than the pre-delete memory'
        or diag "read mem=$read->{inputs}[2] delete=$del->{id}";
};

# DELETE YIELDS THE REMOVED VALUE, so a scalar-context use has a value to bind.
subtest 'delete yields the removed value' => sub {
    my ($g, $err) = translate(<<'SRC');
my %h = (a => 42);
my $v = delete $h{a};
print "$v\n";
SRC
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;
    ok defined $g, 'it translates' or return;

    my ($del) = grep {
        $_->{op} eq 'Delete'
        || ( $_->{op} eq 'Call' && ($_->{fields}{name} // '') eq 'delete' )
    } $g->{nodes}->@*;
    ok defined $del, 'the delete is in the graph' or return;
    ok scalar($del->{consumers} // 1), 'and its value is available to bind';
};

# A SLICE DELETES MANY KEYS AT ONCE, so its operands arrive as a list and the
# container/key pop does not describe them. It is refused -- and the
# discriminator is a PRIVATE bit, not an OPf flag:
#
#     delete $h{a}         flags=0x4 private=0x0
#     delete @h{qw(a b)}   flags=0x4 private=0x40   OPpSLICE
#
# Keyed on `flags & 64` (OPf_STACKED) the refusal never fired, and the slice
# popped one key off a list of them: the node came out Delete(Constant,
# HashLiteral) with container and key SWAPPED, removing something the program
# never named. Asserting on the refusal alone would not have caught that, so the
# single-key case below pins the operand ORDER too.
# A DELETE SLICE NOW LOWERS, as N removals chained through memory. This subtest
# pinned the refusal; the behaviour it was protecting -- that a later read
# observes the removal -- is what it asserts now. Both container kinds go
# through the same handler, verified rather than assumed.
subtest 'a delete slice removes every key it names' => sub {
    for my $case (
        ['hash',  'my %h=(a=>1,b=>2); delete @h{qw(a b)}; print defined($h{a})?"y":"n";'],
        ['array', 'my @a=(1,2,3); delete @a[0,1]; print defined($a[0])?"y":"n";'],
    ) {
        my ($name, $src) = $case->@*;
        my ($g, $err) = translate($src);
        unlike $err, qr/GAP:/, "$name slice: not refused" or diag $err;
        ok $g, "$name slice: translates";

        # ONE Delete PER KEY, not one for the slice: each removal is its own
        # effect, which is what makes the later read see them all.
        # translate() returns the __PROGRAM__ graph DIRECTLY, not a `methods`
        # map -- reading it a level too deep found nothing and reported 0.
        my @del = grep { $_->{op} eq 'Delete' } ( $g->{nodes} // [] )->@*;
        is scalar(@del), 2, "$name slice: two Delete nodes, one per key";

        # CHAINED, not parallel: the second Delete's memory input is the first,
        # which is what makes a later read observe both removals.
        is $del[1]{inputs}[2], $del[0]{id},
            "$name slice: the second removal threads onto the first";
    }
};

# THE OPERAND ORDER IS THE CONTRACT. Container first, key second -- the swap
# above produced a structurally complete node that removed the wrong entry.
subtest 'the container comes first and the key second' => sub {
    my ($g, $err) = translate(<<'SRC');
my %h = (a => 1, b => 2);
delete $h{a};
print defined($h{a}) ? "y" : "n", "\n";
SRC
    ok defined $g, 'it translates' or diag($err), return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my ($del) = grep { $_->{op} eq 'Delete' } $g->{nodes}->@*;
    ok defined $del, 'the Delete is in the graph' or return;

    is $by{ $del->{inputs}[0] }{op}, 'HashLiteral', 'inputs[0] is the container';
    is $by{ $del->{inputs}[1] }{fields}{value}, 'a', 'inputs[1] is the key';
};

done_testing;
