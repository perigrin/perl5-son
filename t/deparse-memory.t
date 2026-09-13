# ABOUTME: Element reads and stores must render so the read observes the right store.
# ABOUTME: This is the defect class the oracle exists for -- a graph that looks complete and computes wrong.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; return;
    }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# AN ELEMENT READ CARRIES ITS MEMORY as inputs[2], and that is the whole point:
# a read threaded to the store before it sees the stored value, a read threaded
# past it sees the old one. Measured on the graph for
#
#     my @a=(1,2,3); $a[0]=7; print $a[0]
#
#     20 Assign     in=[Subscript, Constant 7]  ctl=19
#     21 Subscript  in=[ArrayLiteral, 0, 20]    <- threaded to the Assign
#
# so the graph SAYS the read observes the store. Whether the emitted program
# agrees is what these check.
# AN ELEMENT STORE IS REFUSED, and the refusal is a finding rather than a
# rendering gap. `my @a = (1,2,3)` leaves NO variable in the graph -- measured,
# the array exists only as an ArrayLiteral value and `@a` is gone -- so
# `$a[0] = 7` arrives as
#
#     Assign(Subscript(ArrayLiteral, 0), 7)
#
# "store into element 0 of this literal", for which there is no Perl:
# `(1,2,3)[0] = 7` is not assignable.
#
# A fresh temporary would make these pass and would be exactly wrong: it is a
# DIFFERENT container from the one every read in the graph names, so the store
# would land where no read looks. "Does the read observe the store" is the
# question the tool exists to answer, so it must not be answered by
# construction. Same loss as keys/values/each (docs/plans/2026-09-06), from the
# store side.
subtest 'an element store into a nameless container refuses' => sub {
    for my $case (
        ['array', 'my @a=(1,2,3); $a[0]=7; print $a[0], "\n";'],
        ['hash',  'my %h=(k=>1); $h{k}=9; print $h{k}, "\n";'],
    ) {
        my ($name, $src) = $case->@*;
        my $data = graph_of($src);
        ok $data, "$name: translates" or next;
        my $d = SoN::Deparse->new;
        is $d->render($data), undef, "$name: refuses rather than guessing";
        like $d->gap, qr/no variable to name/, "$name: ... naming the loss";
    }
};

subtest 'plain element reads' => sub {
    round_trips('my @a=(1,2,3); print $a[1], "\n";',     'array read');
    round_trips('my %h=(k=>9); print $h{k}, "\n";',      'hash read');
    round_trips('my @a=(1,2,3); print scalar(@a), "\n";', 'array count');
};

done_testing;
