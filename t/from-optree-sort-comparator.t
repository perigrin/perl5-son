# ABOUTME: sort with an unfoldable comparator lowers; the body is its own graph, named by the sort.
# ABOUTME: Inline blocks and named subs both land in the comparator slot and both must be reachable.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub methods_of ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    return $data->{methods};
}

# perl FOLDS the standard comparators into flags on the op, so `sort { $a <=> $b }`
# carries no block and already lowers with sort_cmp/sort_order. Anything perl
# could not fold arrives as a real subtree in the comparator slot, and dropping
# it would leave the list unsorted -- so it was refused.
#
# Measured -- all three unfoldable forms set OPf_STACKED and put a `null` at
# kid[1], differing only in what sits under it:
#
#     sort { $b->[1] <=> $a->[1] } ...   scope    an inline block
#     sort bylen ...                     const    a named CV
#     sort $subref ...                   padsv    a runtime value
#
# The comparator reads $a and $b as PACKAGE GLOBALS through the stash (measured:
# the multideref aux carries B::GV(a) / B::GV(b)), which is the binding
# environment EntryDef/EntryWrite now supply.
subtest 'an inline comparator block lowers and its body is reachable' => sub {
    my $m = methods_of(<<'SRC');
my @k = sort { $b->[1] <=> $a->[1] } ([1,2],[3,4]);
print scalar(@k), "\n";
SRC
    ok defined $m, 'it translates at all' or return;

    my ($call) = grep { $_->{op} eq 'Call' && ($_->{fields}{name} // '') =~ /sort/ }
                 $m->{'main::__PROGRAM__'}{nodes}->@*;
    ok defined $call, 'the sort is in the graph' or return;

    my $cmp = $call->{fields}{sort_cmp_body};
    ok defined $cmp, 'the sort names its comparator body';

    ok exists $m->{$cmp}, "the comparator body $cmp is its own methods entry"
        or return;

    # THE BODY MUST ACTUALLY CONTAIN THE COMPARISON. An empty or stub body
    # would satisfy "a name reaches a graph" while still dropping the ordering.
    my @ops = map { $_->{op} } $m->{$cmp}{nodes}->@*;
    ok scalar(grep { $_ eq 'NumCmp' } @ops),
        'the comparator body holds the numeric comparison'
        or diag "body ops: @ops";
};

# A named comparator is a reference to a CV that is ALREADY translated as its
# own methods entry. It needs no body extraction -- only the name on the wire.
subtest 'a named comparator sub lowers and names the existing CV' => sub {
    my $m = methods_of(<<'SRC');
sub bylen { length($a) <=> length($b) }
my @k = sort bylen ("aaa", "b", "cc");
print scalar(@k), "\n";
SRC
    ok defined $m, 'it translates at all' or return;

    my ($call) = grep { $_->{op} eq 'Call' && ($_->{fields}{name} // '') =~ /sort/ }
                 $m->{'main::__PROGRAM__'}{nodes}->@*;
    ok defined $call, 'the sort is in the graph' or return;

    is $call->{fields}{sort_cmp_body}, 'main::bylen',
        'the comparator names the already-translated sub';

    ok exists $m->{'main::bylen'}, 'and that sub is on the wire';

    # THE COMPARATOR NAME IS NOT AN ELEMENT TO SORT. It is pushed onto the
    # stack ahead of the list (const[PV "bylen"]/BARE), so the generic argument
    # collection took it as inputs[0]: the graph sorted FOUR items where perl
    # sorts three, with the literal "bylen" among them.
    is scalar($call->{inputs}->@*), 3,
        'the sort takes the three list elements, not the comparator name';

    my %by = map { $_->{id} => $_ } $m->{'main::__PROGRAM__'}{nodes}->@*;
    my @vals = map { $by{$_}{fields}{value} // '' } $call->{inputs}->@*;
    ok !(grep { $_ eq 'bylen' } @vals),
        'and the comparator name is not among them'
        or diag "inputs: @vals";
};

# A comparator chosen at RUNTIME cannot be resolved statically, so it stays
# refused rather than silently sorting by the wrong order.
subtest 'a runtime subref comparator still refuses' => sub {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh "my \$c = sub { \$a <=> \$b };\nmy \@k = sort \$c (3,1,2);\nprint scalar(\@k);\n";
    close $fh;
    my $err = qx($^X -Ilib -MO=SoN,json,package=main $file 2>&1 >/dev/null);
    unlink $file;
    like $err, qr/GAP:.*comparator/,
        'it refuses rather than dropping the ordering';
};

done_testing;
