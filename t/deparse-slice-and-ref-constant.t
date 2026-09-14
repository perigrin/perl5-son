# ABOUTME: An array slice renders as @a[LIST]; a `ref` Constant is \VALUE.
# ABOUTME: Both come from the corpus -- comp/term.t's "@foo[0..1]" and base/rs.t's $/ = \2.

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

# AN ARRAY SLICE TAKES A LIST OF INDICES. Measured on comp/term.t's
# `"@foo[0..1]b"`:
#
#     Slice(158) in=[157:PostfixDeref, 141:ArrayLiteral @main::foo]  stamp=List
#
# so input 0 is the INDEX LIST and input 1 is the container -- the container
# second, which is the opposite of Subscript's order and the thing a
# positional guess would get backwards.
#
# THE ORDER IS OBSERVABLE. A slice with its operands swapped indexes the
# indices by the array, which for `@foo[0..1]` over (1,2,3) still yields two
# elements -- plausible output, wrong values. So the check is the CONTENTS.
subtest 'an array slice round-trips' => sub {
    round_trips(<<'SRC', 'a two-element slice');
my @foo = (10, 20, 30);
print "[@foo[0..1]]\n";
SRC

    round_trips(<<'SRC', 'a slice that is not a prefix');
my @foo = (10, 20, 30);
print "[@foo[1..2]]\n";
SRC

    round_trips(<<'SRC', 'a single-element slice');
my @foo = (10, 20, 30);
print "[@foo[1]]\n";
SRC
};

# A `ref` CONSTANT IS \VALUE. base/rs.t sets `$/ = \2`, the record-separator
# form that reads fixed-size records -- measured, `Constant const_type=ref
# value=2`, read by an EntryWrite into $/.
#
# THE VALUE IS THE REFERENT, not the reference, so it is emitted with the
# backslash. Dropping it would assign the NUMBER 2 to $/, which sets the
# separator to the string "2" -- a program that runs and reads different
# records.
subtest 'a ref Constant round-trips' => sub {
    round_trips(<<'SRC', 'fixed-length records via $/ = \N');
my $f = "rsc.$$.tmp";
open(W, ">$f"); print W "abcdefgh"; close(W);
{
    local $/ = \3;
    open(R, "<$f");
    my @rec = <R>;
    close(R);
    print "n=", scalar(@rec), "\n";
    print "[$_]\n" for @rec;
}
unlink $f;
SRC
};

done_testing;
