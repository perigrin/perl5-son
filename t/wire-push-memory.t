# ABOUTME: push/unshift thread on memory so a later read sees the new length.
# ABOUTME: shift/pop were already modelled this way; these were refused.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    my $w = (length $out && $out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    my @n = $w ? (map { { $_->%*, ($_->{fields} // {})->%* } }
                  ($w->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*) : ();
    return (\@n, $err);
}

# THE REFUSAL WAS RIGHT AND THE MODEL ALREADY EXISTS. Its own comment says
# shift/pop ARE memory-SSA modelled -- "the Call becomes the new memory
# version, so a later whole-array read observes the mutation" -- and that
# push/unshift/splice are not, so `my @b=@a; push @b,3; scalar @b` gave 2 not
# 3. A silent miscompile, correctly refused.
#
# What was missing is the same threading applied one builtin over: memory in,
# control pinned, the Call becomes the new memory version.
#
# Measured on 5.42.0: push returns the NEW LENGTH (an Int), not the array.
#     my @a=(1,2); push @a,3,4   returns 4, array is 1,2,3,4
#     my @c; unshift @c,9        returns 1
#
# perl's own t/comp/require.t and t/comp/utf.t both hit this.
# STILL REFUSED, and the refusal is doing real work. Threading push onto the
# memory chain is NOT sufficient on its own: I tried it and the graph still
# said 2 where perl says 3, because the later READ does not consult memory.
#
#     my @a=(1,2); push @a, 3; print scalar(@a);
#     with push threaded:  Count(ArrayLiteral#5)   <- the PRE-push array
#     Call(push, %5, %10, MemStart)                <- correctly threaded
#
# Count extends UnaryOp: one input, no memory slot. Making an aggregate read
# memory-dependent changes that node's arity, every construction site, and the
# consumer's contract -- a wire question, not a producer-local fix. So push
# keeps refusing rather than shipping a graph that reads the pre-mutation
# binding.
subtest 'push is refused until an aggregate read can observe memory' => sub {
    my (undef, $err) = wire('my @a=(1,2); push @a, 3; print scalar(@a);', 'push_basic');
    like $err, qr/GAP/, 'refused rather than silently reading the old length';
};

# THE MUTATION MUST BE OBSERVABLE. This is the assertion the refusal existed to
# protect: a later read has to see the new length, which means the read's
# memory input must be the push, not MemStart.
subtest 'a later read observes the push' => sub {
    my ($n, $err) = wire('my @a=(1,2); push @a, 3; print scalar(@a);', 'push_observed');
  SKIP: {
        skip "refused: $err", 1 if $err =~ /GAP/;
        my %byid = map { $_->{id} => $_ } $n->@*;
        my ($count) = grep { $_->{op} eq 'Count' } $n->@*;
        ok defined $count, 'the scalar(@a) Count exists' or skip 'no Count', 1;
        # walk back from Count: it must reach the push Call
        my (@q, %seen) = (($count->{inputs} // [])->@*);
        my $reaches = 0;
        while (my $id = shift @q) {
            next if $seen{$id}++;
            my $nd = $byid{$id} or next;
            $reaches = 1, last if ($nd->{name} // '') eq 'push';
            push @q, ($nd->{inputs} // [])->@*;
        }
        ok $reaches, 'the later read reaches the push, not the pre-push binding';
    }
};

# PUSH YIELDS THE NEW LENGTH, an Int -- not the array and not the pushed value.
subtest 'push yields an Int length' => sub {
    my ($n, $err) = wire('my @a=(1,2); my $n = push @a, 3; print $n;', 'push_value');
  SKIP: {
        skip "refused", 1 if $err =~ /GAP/;
        my ($p) = grep { ($_->{name} // '') eq 'push' } $n->@*;
        ok defined $p, 'the push Call exists' or skip 'no push', 1;
        is $p->{stamp}, 'Int', 'stamped Int -- the new length';
    }
};

subtest 'unshift is refused for the same reason' => sub {
    my (undef, $err) = wire('my @a=(2,3); unshift @a, 1; print scalar(@a);', 'unshift');
    like $err, qr/GAP/, 'refused, same missing capability';
};

# SPLICE STAYS REFUSED -- it removes as well as inserts and its return value is
# the removed elements, a different shape from push's length. Asserted so it is
# not swept up by a fix aimed at push.
subtest 'splice still refuses' => sub {
    my (undef, $err) = wire('my @a=(1,2,3); splice(@a,1,1); print scalar(@a);', 'splice');
    like $err, qr/GAP/, 'splice is still refused';
};

# SHIFT/POP were already modelled and must stay working.
subtest 'shift and pop are unaffected' => sub {
    my (undef, $e1) = wire('my @a=(1,2); my $x = shift @a; print $x;', 'shift_still');
    unlike $e1, qr/GAP|INTERNAL/, 'shift still translates';
    my (undef, $e2) = wire('my @a=(1,2); my $x = pop @a; print $x;', 'pop_still');
    unlike $e2, qr/GAP|INTERNAL/, 'pop still translates';
};

done_testing;
