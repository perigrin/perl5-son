# ABOUTME: A statement after a nested loop is part of the enclosing loop's body.
# ABOUTME: The body's own terminator is the unstack; a leaveloop here is the inner one's.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(timeout 10 $^X $f 2>&1); unlink $f; return $out;
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

# THE BODY'S OWN TERMINATOR IS THE `unstack`. A `leaveloop` this walk reaches
# belongs to a NESTED loop or bare block, so stopping there discarded every
# statement after it -- measured:
#
#     for (@a) { for (7,8) { } print "X" }
#       perl  : XX
#       graph : the print was simply absent
#
#     my @a=(1,2); for (@a) { for (7,8) {} $_ = $_ + 100 }
#       perl    : 101 102
#       emitted : 1 2
#
# A silent DROP. It was masked until the nested-foreach iterator leak was
# fixed, because that leak made the outer loop emit a store the deparse
# refused for an unrelated reason.
#
# THE STATEMENT MUST RUN EVERY ITERATION, which is what a count shows: one
# that runs once, or not at all, still prints something.
subtest 'a statement after a nested loop' => sub {
    round_trips(<<'SRC', 'a print after an inner loop');
my @a = (1, 2);
for (@a) { for (7,8) { } print "X" }
print "\n";
SRC

    round_trips(<<'SRC', 'a write after an inner loop');
my @a = (1, 2);
for (@a) { for (7,8) { } $_ = $_ + 100 }
print "@a\n";
SRC

    round_trips(<<'SRC', 'and the inner loop still runs');
my @v;
for (1,2) { for (7,8) { push @v, $_ } push @v, "-" }
print "@v\n";
SRC
};

# A NESTED LOOP THAT ENDS THE BODY must not regress -- it is the shape that
# already worked, and it reaches `leaveloop -> unstack` rather than
# `leaveloop -> nextstate`.
subtest 'a nested loop that ends the body' => sub {
    round_trips(<<'SRC', 'nothing after the inner loop');
my @v;
for (1,2) { for (7,8) { push @v, $_ } }
print "@v\n";
SRC
};

done_testing;
