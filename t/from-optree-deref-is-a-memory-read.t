# ABOUTME: `@$r` reads the referent through memory; flattening the literal substitutes stale values.
# ABOUTME: A runtime ref is the same node, not a different problem -- PostfixDeref carries the sigil.

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

# A RUNTIME REF DEREFS THE SAME WAY A LITERAL ONE DOES. The refusal said a
# runtime ref "cannot be statically flattened", which is true and is not the
# question: the deref is a READ of the referent, and a read does not need its
# contents known at compile time. PostfixDeref is the existing vocabulary --
# it carries the sigil and is already built for `$$r`.
subtest 'a runtime array-ref derefs in list context' => sub {
    for my $case (
        ['from a sub',   'sub f { [1,2,3] } my $r = f(); my @c = @$r; print scalar(@c);'],
        ['from a param', 'sub g { my ($r)=@_; my @c = @$r; return scalar(@c) } print g([1,2]);'],
    ) {
        my ($name, $src) = $case->@*;
        my (undef, $err) = translate($src);
        unlike $err, qr/GAP:/, "$name: not refused" or diag $err;
    }
};

subtest 'a runtime hash-ref derefs in list context' => sub {
    my (undef, $err) = translate('sub f { {a=>1} } my $r=f(); my @k = keys %$r; print scalar(@k);');
    unlike $err, qr/GAP:/, 'not refused' or diag $err;
};

# THE LITERAL PATH WAS ALREADY WRONG, and this is the defect that matters more
# than the refusal: flattening the ArrayRef substitutes its CONSTRUCTION-TIME
# elements for a memory read, so any mutation between construction and deref is
# lost. Measured:
#
#     my $r=[1,2]; $r->[0]=9; my @c=@$r; print "@c"
#       perl : 9 2
#       before: join took the original Constants 1 and 2 -- printed "1 2"
#
#     my $r=[1,2]; my $s=$r; $s->[0]=9; my @c=@$r
#       same, through an alias
#
# The element-read path made exactly this correction already: "a
# value-substitution read-back cache was here; it was unsound under aliasing
# and is gone -- the fold is deferred to a later alias-aware optimization pass."
subtest 'a deref observes stores to the referent' => sub {
    my ($g, $err) = translate('my $r=[1,2]; $r->[0]=9; my @c=@$r; print "@c";');
    ok defined $g, 'it translates' or diag($err), return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my ($join) = grep {
        $_->{op} eq 'Call' && ($_->{fields}{name} // '') eq 'join'
    } $g->{nodes}->@*;
    ok defined $join, 'the interpolation is a join' or return;

    # THE ELEMENTS, NOT THE SEPARATOR. join's inputs[0] is the separator (which
    # here happens to reach the Assign, because the store's value feeds the
    # interpolation) -- an earlier version of this assertion searched ALL the
    # operands and passed for that reason while the elements were still the
    # stale Constants. The elements are inputs[1..].
    my @elems = ($join->{inputs}->@*)[1 .. $join->{inputs}->$#*];
    ok scalar(@elems), 'the join has elements to check' or return;

    my $stale = grep {
        ( $by{$_}{op} // '' ) eq 'Constant'
    } @elems;
    ok !$stale,
        'the deref does not substitute the literal\'s construction-time values'
        or diag "join elements: "
              . join ',', map { ($by{$_}{op} // '?')
                              . '/' . ($by{$_}{fields}{value} // '') } @elems;
};

# A push through the ref is the same question with a different mutator.
subtest 'a deref observes a push to the referent' => sub {
    my ($g, $err) = translate('my $r=[1,2]; push @$r,3; my @c=@$r; print scalar(@c);');
    ok defined $g, 'it translates' or diag($err), return;

    my ($push) = grep {
        $_->{op} eq 'Call' && ($_->{fields}{name} // '') eq 'push'
    } $g->{nodes}->@*;
    ok defined $push, 'the push is in the graph' or return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    # THE PUSH MUST NAME THE CONTAINER. It took [Constant,Constant,Constant] --
    # the flattened elements -- so it appended to nothing.
    my $first = $by{ $push->{inputs}[0] };
    isnt $first->{op}, 'Constant',
        'push targets the container, not a flattened element'
        or diag "push inputs: "
              . join ',', map { $by{$_}{op} // '?' } $push->{inputs}->@*;
};

done_testing;
