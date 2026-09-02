# ABOUTME: map/grep in scalar context are COUNTS, not their result list.
# ABOUTME: Both context polarities asserted, because one alone agrees with the bug.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub run_wire ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    my $wire = length($out) && $out =~ /^\{/ ? JSON::PP->new->decode($out) : undef;
    my $nodes = $wire
        ? [ map { { $_->%*, ($_->{fields} // {})->%* } }
            ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@* ]
        : [];
    return ($nodes, $err);
}

# MAP AND GREP IN SCALAR CONTEXT ARE COUNTS. Measured on 5.42.0:
#
#     my $n = map { $_*2 } (1,2,3)    3    the number of results
#     my $n = grep { $_>1 } (1,2,3)   2    the number that matched
#
# Both lower to a loop accumulating a ListAppend, and the scalar reading took
# the ACCUMULATOR: `print $n` emitted Print(Coerce(Phi:Array -> Str)),
# stringifying the result list where perl prints a count. Same class as scalar
# reverse -- a context-sensitive op given one reading.
#
# THE PRINTED VALUE IS THE TEST. A Count node must be reachable from the print;
# asserting only "not Coerce" would pass on a graph that dropped the value.
sub prints_a_count ($nodes) {
    my %byid = map { $_->{id} => $_ } $nodes->@*;
    my ($print) = grep { $_->{op} eq 'Print' } $nodes->@*;
    return 0 unless $print;
    my (@q, %seen) = (($print->{inputs} // [])->@*);
    while (my $id = shift @q) {
        next if $seen{$id}++;
        my $n = $byid{$id} or next;
        return 1 if $n->{op} eq 'Count';
        push @q, ($n->{inputs} // [])->@*;
    }
    return 0;
}

subtest 'scalar map is a count, not its result list' => sub {
    my ($nodes, $err) = run_wire('my @a=(1,2,3); my $n = map { $_*2 } @a; print $n;', 'map_s');
  SKIP: {
        skip "refused: $err", 1 if $err =~ /GAP/;
        ok prints_a_count($nodes),
            'the printed value reaches a Count, not the accumulated list';
    }
};

subtest 'scalar grep is a count, not its result list' => sub {
    my ($nodes, $err) = run_wire('my @a=(1,2,3); my $n = grep { $_>1 } @a; print $n;', 'grep_s');
  SKIP: {
        skip "refused: $err", 1 if $err =~ /GAP/;
        ok prints_a_count($nodes),
            'the printed value reaches a Count, not the accumulated list';
    }
};

# THE OTHER POLARITY, written from the start rather than after a bug. LIST
# context must still yield the elements -- a "fix" that made both contexts a
# count would satisfy the two subtests above and destroy this one.
subtest 'list map and grep still yield their elements' => sub {
    for my $case (
        ['my @a=(1,2,3); my @m = map { $_*2 } @a; print "@m";',  'map_l'],
        ['my @a=(1,2,3); my @g = grep { $_>1 } @a; print "@g";', 'grep_l'],
    ) {
        my ($src, $name) = $case->@*;
        my ($nodes, $err) = run_wire($src, $name);
      SKIP: {
            skip "refused: $err", 1 if $err =~ /GAP/;
            ok !prints_a_count($nodes),
                "$name: list context prints the elements, not a count";
        }
    }
};

# SPLIT IN SCALAR CONTEXT DIED INTERNALLY -- "No mark on mark stack" -- which is
# the failure class that MASKS an honest refusal: the reader is sent after a
# simulator bug instead of a named construct. Whatever the producer decides
# about split's scalar reading, it must not crash.
subtest 'scalar split does not crash the translator' => sub {
    my (undef, $err) = run_wire('my $n = split(/,/, "a,b"); print $n;', 'split_s');
    unlike $err, qr/INTERNAL ERROR/,
        'scalar split refuses or lowers, but does not die internally';
};

done_testing;
