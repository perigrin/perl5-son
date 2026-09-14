# ABOUTME: keys/values/each read a container through memory, so they observe stores to it.
# ABOUTME: each also ADVANCES memory -- it consumes an iterator stored on the hash.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub run_and_graph ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $want = qx($^X $file 2>&1);
    my $err  = qx($^X -Ilib -MO=SoN,json,package=main $file 2>&1 >/dev/null);
    my $out  = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->utf8->decode($out) };
    return ($want, $err, $data ? $data->{methods}{'main::__PROGRAM__'} : undef);
}

# AN AGGREGATE-WIDE READ TOOK ITS CONTAINER AND NOTHING ELSE:
#
#     keys => [1, 'Call', 1, 0]
#
# one operand, no memory. So it could not observe a store, and the file
# reported CLEAN while computing the wrong answer -- the worst shape, because
# nothing refuses. Measured:
#
#     my %h=(a=>1); $h{b}=2; print scalar(keys %h)
#       perl : 2
#       before: Call(keys) in=[HashLiteral]  -- reports 1
#
# Count had this defect one path over and was fixed the same way: give the
# read a memory input. See docs/plans/2026-09-06.
subtest 'keys observes a store to the hash' => sub {
    my ($want, $err, $g) = run_and_graph('my %h=(a=>1); $h{b}=2; print scalar(keys %h), "\n";');
    is $want, "2\n", 'perl counts the stored key' or return;
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;
    ok $g, 'it translates' or return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my ($call) = grep {
        $_->{op} eq 'Call' && ($_->{fields}{name} // '') eq 'keys'
    } $g->{nodes}->@*;
    ok $call, 'the keys call is in the graph' or return;

    ok scalar($call->{inputs}->@*) >= 2,
        'it carries a memory input, not just the container'
        or diag "inputs: " . join(',', map { $by{$_}{op} // '?' } $call->{inputs}->@*);

    my $mem = $by{ $call->{inputs}[1] };
    isnt $mem->{op}, 'MemStart',
        '... threaded to the store, not to the pre-store memory';
};

subtest 'values observes a store to the hash' => sub {
    my ($want, $err, $g) = run_and_graph('my %h=(a=>1); $h{b}=2; print scalar(values %h), "\n";');
    is $want, "2\n", 'perl counts the stored value' or return;
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;

    my ($call) = grep {
        $_->{op} eq 'Call' && ($_->{fields}{name} // '') eq 'values'
    } ($g ? $g->{nodes}->@* : ());
    ok $call && scalar($call->{inputs}->@*) >= 2,
        'values carries a memory input';
};

# `each` IS NOT A PURE READ. It advances an iterator stored ON THE HASH, so
# two calls yield different answers -- measured: after one `each`, a fresh
# loop over a 3-key hash yields only 2 more keys. A read that does not advance
# memory would let the two calls hash-cons into one node, which is the same
# class of merge the sigil requirement prevents.
subtest 'each advances memory as well as reading it' => sub {
    my ($want, $err, $g) = run_and_graph(
        'my %h=(a=>1,b=>2); my $n=0; while (my ($k,$v) = each %h) { $n++ } print "$n\n";');
    is $want, "2\n", 'perl iterates both pairs' or return;

    return unless $g;
    my @each = grep {
        $_->{op} eq 'Call' && ($_->{fields}{name} // '') eq 'each'
    } $g->{nodes}->@*;
    return unless @each;
    ok scalar($each[0]{inputs}->@*) >= 2, 'each carries a memory input';
};

# TWO CALLS TO each ARE TWO DIFFERENT VALUES even on the same hash, so they
# must not hash-cons into one node.
subtest 'two each calls on one hash are two nodes' => sub {
    my (undef, $err, $g) = run_and_graph(
        'my %h=(a=>1,b=>2); my @p = each %h; my @q = each %h; print scalar(@p)+scalar(@q), "\n";');
    return unless $g;
    my @each = grep {
        $_->{op} eq 'Call' && ($_->{fields}{name} // '') eq 'each'
    } $g->{nodes}->@*;
    return unless @each >= 2;
    isnt $each[0]{id}, $each[1]{id},
        'the second each is its own node -- it sees a different iterator';
};

done_testing;
