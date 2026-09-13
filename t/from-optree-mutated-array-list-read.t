# ABOUTME: A list-context read of a mutated array reads it as it now stands, not as constructed.
# ABOUTME: The same memory-threaded read PostfixDeref already builds for @$r.

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

# THE BINDING IS THE PRE-MUTATION LITERAL. A bare `@a` in list context pushed
# the ArrayLiteral's ORIGINAL elements -- the array as first constructed --
# so any read after a push/shift/splice was stale:
#
#     my @a=(1,2,3); shift @a; print "@a"
#       perl : 2 3
#       before: join($", 1, 2, 3)  -- the three original constants
#
# It was refused rather than left silent, correctly. The refusal's own message
# said there is "no node for the elements of @a as they now are".
#
# THERE IS ONE, AND IT IS ALREADY BUILT. PostfixDeref does exactly this for
# `@$r` -- measured on `my $r=[1,2,3]; push @$r,4; my @c=@$r`:
#
#     10 PostfixDeref in=[ArrayLiteral, Call:push]   the read AFTER the push
#     11 Count        in=[10, Call:push]             counts 4, matching perl
#
# Same shape, and Count was fixed the same way one path over: give the read a
# memory input and it observes the mutation.
subtest 'a list read after shift sees the mutated array' => sub {
    my ($want, $err, $g) = run_and_graph('my @a=(1,2,3); shift @a; print "@a\n";');
    is $want, "2 3\n", 'perl drops the first element' or return;
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;
    ok $g, 'it translates' or return;

    # THE READ MUST CARRY MEMORY. Without it the node cannot observe the
    # shift, whatever else the graph looks like.
    my ($read) = grep {
        $_->{op} eq 'PostfixDeref' && ($_->{inputs} // [])->@* >= 2
    } $g->{nodes}->@*;
    ok $read, 'the list read is a memory-threaded PostfixDeref' or return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my $mem = $by{ $read->{inputs}[1] };
    isnt $mem->{op}, 'MemStart',
        '... threaded to the mutation, not to the pre-mutation memory';
};

subtest 'a list read after push sees the mutated array' => sub {
    my ($want, $err, $g) = run_and_graph('my @a=(1,2); push @a,3; print "@a\n";');
    is $want, "1 2 3\n", 'perl appends' or return;
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;
    ok $g, 'it translates';
};

# AN UNMUTATED ARRAY MUST NOT REGRESS. The flatten shortcut is correct when
# nothing has written to the slot, and it is the common case.
subtest 'an unmutated array still lowers' => sub {
    my ($want, $err, $g) = run_and_graph('my @a=(1,2,3); print "@a\n";');
    is $want, "1 2 3\n", 'perl prints the elements' or return;
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;
    ok $g, 'it translates';
};

done_testing;
