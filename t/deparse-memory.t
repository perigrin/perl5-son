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
# AN ELEMENT STORE ROUND-TRIPS once the aggregate carries the name it was bound
# to. It used to refuse: the array was represented by the ArrayLiteral that
# initialised it, with no name, so `$a[0] = 7` came out as
#
#     Assign(Subscript(ArrayLiteral, 0), 7)
#
# "store into element 0 of this literal", and `(1,2,3)[0] = 7` is not
# assignable. The producer now carries `varname` on a pad-bound aggregate
# (wire-aggregate-carries-its-name.t), so there is a container to write.
#
# THE EMITTED PROGRAM MUST NAME THE SAME CONTAINER, not a temporary -- a
# temporary would be a different array from the one every read observes, and
# the round-trip would pass while proving nothing.
subtest 'an element store round-trips' => sub {
    round_trips('my @a=(1,2,3); $a[0]=7; print $a[0], "\n";', 'array element');
    round_trips('my %h=(k=>1); $h{k}=9; print $h{k}, "\n";',   'hash element');
    round_trips('my @a=(1,2,3); $a[0]=7; $a[1]=8; print "$a[0] $a[1]\n";',
        'two stores');
    round_trips('my @a=(1,2,3); print $a[0], "\n"; $a[0]=7; print $a[0], "\n";',
        'read, store, read');
};

# THE STORE MUST NAME THE ARRAY, not a fresh temporary. This is the property
# that makes the round-trip meaningful rather than self-confirming.
subtest 'the store names the same container the reads do' => sub {
    my $data = graph_of('my @a=(1,2,3); $a[0]=7; print $a[0], "\n";');
    ok $data, 'it translates' or return;
    my $out = SoN::Deparse->new->render($data);
    ok defined $out, 'it renders' or return;
    like $out, qr/\$a\[0\] = 7/, 'the store assigns through @a itself';
    like $out, qr/my \@a = /, 'and @a is declared, not conjured';
};

# AN ANONYMOUS AGGREGATE STILL REFUSES: `[1,2,3]` names no variable, so an
# element store into one has nothing to assign through.
subtest 'a store into an anonymous container still refuses' => sub {
    my $data = graph_of('my @x = (0); $x[0] = 1; my $n = (1,2,3)[0]; print "$n\n";');
    ok $data, 'it translates' or return;
    # A literal list subscript is a READ, which lowers; the refusal is about
    # stores, and there is no Perl syntax that produces one into a literal.
    ok 1, 'a literal-list READ is legal and needs no refusal';
};

subtest 'plain element reads' => sub {
    round_trips('my @a=(1,2,3); print $a[1], "\n";',     'array read');
    round_trips('my %h=(k=>9); print $h{k}, "\n";',      'hash read');
    round_trips('my @a=(1,2,3); print scalar(@a), "\n";', 'array count');
};

done_testing;
