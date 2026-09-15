# ABOUTME: lslice is two mark-delimited lists -- indices, then the values.
# ABOUTME: A fixed arity of 2 took the last two stack entries and dropped the rest.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub graph_of ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    return $data->{methods}{'main::__PROGRAM__'};
}

# `(qw(p q r))[1]` is `lslice` over TWO mark-delimited lists -- measured on
# the optree, which does NOT fold it:
#
#     pushmark; pushmark; const[IV 1];        <- the index list
#     pushmark; const "p"; const "q"; const "r";   <- the value list
#     lslice
#
# OpMap declared it `[2, 'Slice', ...]`, a fixed arity, so the generic
# dispatch popped the last TWO stack entries: `Slice("q", "r")`. The index
# and the first value were dropped, and "p" leaked into the enclosing
# print's arguments.
#
# Every other slice op in that table -- aslice, kvaslice, hslice, kvhslice --
# is already declared 'mark'. lslice was the row that got missed.
subtest 'a list slice keeps every value and every index' => sub {
    my $g = graph_of(qq{print( (qw(p q r))[1], "\\n" );\n});
    ok defined $g, 'it translates' or return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my ($slice) = grep { $_->{op} eq 'Slice' } $g->{nodes}->@*;
    ok defined $slice, 'a Slice is in the graph' or return;

    my @in = map { $by{$_} } ($slice->{inputs} // [])->@*;
    my @vals = map { $_->{fields}{value} // '' }
               grep { ($_->{op} // '') eq 'Constant' } @in;

    # All three values must be present. Two means the mark was ignored.
    ok scalar(grep { $_ eq 'p' } @vals), 'the first value survives';
    ok scalar(grep { $_ eq 'q' } @vals), 'the second value survives';
    ok scalar(grep { $_ eq 'r' } @vals), 'the third value survives';
    ok scalar(grep { $_ eq '1' } @vals), 'and so does the index';
};

# A single-element qw is the shape base/lex.t uses, and it is where the
# defect was a silent WRONG ANSWER rather than a refusal: the emitted
# program printed nothing where perl prints "b".
subtest 'a one-element list slice still names its value' => sub {
    my $g = graph_of(qq{print( (qw(b))[0], "\\n" );\n});
    ok defined $g, 'it translates' or return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my ($slice) = grep { $_->{op} eq 'Slice' } $g->{nodes}->@*;
    ok defined $slice, 'a Slice is in the graph' or return;

    my @vals = map { $by{$_}{fields}{value} // '' }
               ($slice->{inputs} // [])->@*;
    ok scalar(grep { $_ eq 'b' } @vals), 'the value is an operand of the Slice';
};

done_testing;
