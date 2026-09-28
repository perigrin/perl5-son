# ABOUTME: `() = LIST` is the count of LIST in scalar context and the empty
# ABOUTME: list in list context -- not LIST itself, which is what flowed on.

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
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>$dir/err);
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

# AN EMPTY LHS RETURNED WITHOUT POPPING THE RHS. The guard was written for
# a padrange-bound LHS, which the suppressed peephole never builds; what
# reaches it is `() = LIST`, and the RHS values stayed on the stack for the
# next consumer -- `$n` became the sort itself, coerced to a string.
# Corpus 120 and 121.
round_trips(<<'SRC', 'the count idiom in scalar context');
my @a = (3, 1, 2);
my $n = () = sort @a;
my $m = () = localtime(0);
print "$n $m\n";
SRC

# IN LIST CONTEXT A LIST ASSIGN YIELDS ITS LHS, which is empty here.
round_trips(<<'SRC', 'an empty list assign in list context is empty');
my @a = (3, 1, 2);
my @c = (() = sort @a);
print scalar(@c), "\n";
SRC

round_trips(<<'SRC', 'a count of several scalars');
my ($x, $y) = (1, 2);
my $n = () = ($x, $y, 7);
print "$n\n";
SRC

# A SCALAR-CONTEXT BUILTIN KEEPS ITS CONTEXT WHEN INLINED. The second half
# of corpus 121: `my $s = localtime` folded into `my @c = ($s)` as
# `(localtime())`, which is list context -- nine elements, not one.
round_trips(<<'SRC', 'a scalar localtime inlined into a list');
my $s = localtime(0);
my @c = ($s);
my $r = reverse("ab", "cd");
my @d = ($r);
print scalar(@c), " ", scalar(@d), " $d[0]\n";
SRC

done_testing;
