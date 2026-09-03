# ABOUTME: A whole-aggregate read must observe a mutation that preceded it.
# ABOUTME: Count had no memory input, so it read the pre-mutation aggregate.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub run_and_wire ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $said = qx{$PERL $file 2>/dev/null};
    my $out  = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    my $w = (length $out && $out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    return ($said, $w, $err);
}

sub prog_nodes ($w) {
    return [ ($w->{methods}{'main::__PROGRAM__'}
             ? $w->{methods}{'main::__PROGRAM__'}{nodes}->@* : ()) ];
}

# A WHOLE-AGGREGATE READ IS MEMORY-DEPENDENT, exactly as an element read is.
# `Count` extended UnaryOp -- ONE input, no memory slot -- so it could not
# observe a mutation no matter how well the mutation itself was threaded.
# Measured before this fix:
#
#     my @a=(1,2,3); shift @a; print scalar(@a);
#       perl:  2
#       graph: Count[ArrayLiteral]  reading the PRE-shift array, and BUILT
#              BEFORE the shift node. Says 3. Silently.
#
# THE MUTATION WAS ALREADY THREADED. shift/pop become the new memory version;
# the defect was entirely on the READ side, which is why threading writes
# harder never fixed it -- and why `push` refusing (it produced the same
# miscompile) while `shift` shipped was an inconsistency rather than a
# difference in difficulty.
subtest 'a count after shift observes the shortened array' => sub {
    my ($said, $w, $err) = run_and_wire(
        'my @a = (1,2,3); shift @a; print scalar(@a);', 'count-shift');
    is $said, '2', 'perl shortens the array' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    my @n = prog_nodes($w)->@*;
    my ($count) = grep { $_->{op} eq 'Count' } @n;
    ok $count, 'a Count is built' or return;

    # The read must carry a memory input, and that input must be the mutation
    # -- not MemStart, which is the pre-mutation version.
    my %by = map { $_->{id} => $_ } @n;
    my @in = ($count->{inputs} // [])->@*;
    cmp_ok scalar(@in), '>=', 2, 'the Count has a memory input';
    my $mem = $by{ $in[-1] } if @in >= 2;
    is +($mem->{op} // ''), 'Call',
        '... and it is the mutation, not the initial memory';
};

# THE SAME DEFECT `push` REFUSED TO SHIP. It GAPed rather than emit a read of
# the pre-push array -- correct under refuse-or-lower, but it meant one member
# of the class refused while its sibling miscompiled.
subtest 'a count after push observes the lengthened array' => sub {
    my ($said, $w, $err) = run_and_wire(
        'my @a = (1,2,3); push @a, 4; print scalar(@a);', 'count-push');
    is $said, '4', 'perl lengthens the array' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers -- no longer refused' or return;

    my @n = prog_nodes($w)->@*;
    my ($count) = grep { $_->{op} eq 'Count' } @n;
    ok $count, 'a Count is built' or return;
    my @in = ($count->{inputs} // [])->@*;
    cmp_ok scalar(@in), '>=', 2, 'the Count is memory-dependent';
};

# TWO READS EITHER SIDE OF A MUTATION ARE DIFFERENT VALUES, and this is what
# the memory input buys that a plain input cannot: without it the two reads
# hash-cons to ONE node, so the graph cannot even express that the length
# changed.
subtest 'reads either side of a mutation are distinct nodes' => sub {
    my ($said, $w, $err) = run_and_wire(
        'my @a=(1,2); my $b=scalar(@a); push @a,3; my $c=scalar(@a);'
      . ' print "$b$c";', 'count-two');
    is $said, '23', 'perl sees 2 then 3' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    my @count = grep { $_->{op} eq 'Count' } prog_nodes($w)->@*;
    is scalar(@count), 2,
        'two reads stay two nodes -- they did not hash-cons to one';
};

# A COUNT OVER A PURE VALUE TAKES NO MEMORY. map/grep's accumulator is a value
# the graph computed, not an aggregate living in memory, so threading it would
# claim a dependency that does not exist and needlessly order the read.
subtest 'a count over a computed list needs no memory' => sub {
    my ($said, $w, $err) = run_and_wire(
        'my @s = map { $_ * 2 } (1,2,3); print scalar(@s);', 'count-map');
    is $said, '3', 'perl counts the mapped list' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    ok scalar(grep { $_->{op} eq 'Count' } prog_nodes($w)->@*),
        'a Count is present for the mapped list';
};

done_testing;
