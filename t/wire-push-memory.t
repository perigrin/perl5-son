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
# THREADING THE WRITE WAS NECESSARY AND NOT SUFFICIENT, and that is why this
# refused for so long. With push threaded the graph STILL said 2 where perl
# says 3:
#
#     my @a=(1,2); push @a, 3; print scalar(@a);
#     Count(ArrayLiteral#5)          <- the PRE-push array
#     Call(push, %5, %10, MemStart)  <- correctly threaded, and irrelevant
#
# `Count` extended UnaryOp: one input, no memory slot, so no amount of care on
# the write side could make the READ observe anything. Count is an Access now
# and takes [aggregate, memory], which is what unblocked this.
#
# shift/pop had the IDENTICAL defect and shipped it rather than refusing --
# `shift @a; scalar @a` said 3 where perl says 2 -- so the class had two
# answers and neither was right. See
# t/wire-aggregate-read-observes-mutation.t.
subtest 'push lowers and threads onto memory' => sub {
    my ($n, $err) = wire('my @a=(1,2); push @a, 3; print scalar(@a);', 'push_basic');
    unlike $err, qr/GAP|INTERNAL/, 'no longer refused' or return;
    my ($p) = grep { ($_->{name} // '') eq 'push' } $n->@*;
    ok defined $p, 'the push Call exists' or return;
    cmp_ok scalar(($p->{inputs} // [])->@*), '>=', 3,
        'it carries array, value and memory';
};

# THE MUTATION MUST BE OBSERVABLE. This is the assertion the refusal existed to
# protect: a later read has to see the new length, which means the read's
# memory input must be the push, not MemStart.
subtest 'a later read observes the push' => sub {
    my ($n, $err) = wire('my @a=(1,2); push @a, 3; print scalar(@a);', 'push_observed');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    {
        my %byid = map { $_->{id} => $_ } $n->@*;
        my ($count) = grep { $_->{op} eq 'Count' } $n->@*;
        ok defined $count, 'the scalar(@a) Count exists' or return;
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
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    {
        my ($p) = grep { ($_->{name} // '') eq 'push' } $n->@*;
        ok defined $p, 'the push Call exists' or return;
        is $p->{stamp}, 'Int', 'stamped Int -- the new length';
    }
};

subtest 'unshift lowers by the same mechanism' => sub {
    my ($n, $err) = wire('my @a=(2,3); unshift @a, 1; print scalar(@a);', 'unshift');
    unlike $err, qr/GAP|INTERNAL/, 'no longer refused' or return;
    ok scalar(grep { ($_->{name} // '') eq 'unshift' } $n->@*),
        'the unshift Call exists';
};

# SPLICE STAYS REFUSED -- it removes as well as inserts and its return value is
# the removed elements, a different shape from push's length. Asserted so it is
# not swept up by a fix aimed at push.
# SPLICE TAKES THE SAME PATH, but its RESULT is different: it yields the
# REMOVED ELEMENTS, not a count. Measured -- `my @d=(1,2,3); splice(@d,1,1)`
# returns the element 2, so stamping it Int (as push/unshift are) would be a
# wrong answer rather than a missing one, and it is deliberately left unstamped.
subtest 'splice lowers too, but is not stamped Int' => sub {
    my ($n, $err) = wire('my @a=(1,2,3); splice(@a,1,1); print scalar(@a);', 'splice');
    unlike $err, qr/GAP|INTERNAL/, 'no longer refused' or return;
    my ($sp) = grep { ($_->{name} // '') eq 'splice' } $n->@*;
    ok defined $sp, 'the splice Call exists' or return;
    isnt +($sp->{stamp} // ''), 'Int',
        'it is not claimed to be a length -- splice returns the removed elements';
};

# SHIFT/POP were already modelled and must stay working.
subtest 'shift and pop are unaffected' => sub {
    my (undef, $e1) = wire('my @a=(1,2); my $x = shift @a; print $x;', 'shift_still');
    unlike $e1, qr/GAP|INTERNAL/, 'shift still translates';
    my (undef, $e2) = wire('my @a=(1,2); my $x = pop @a; print $x;', 'pop_still');
    unlike $e2, qr/GAP|INTERNAL/, 'pop still translates';
};

done_testing;
