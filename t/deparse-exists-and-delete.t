# ABOUTME: `exists` asks membership, which is a different question from definedness.
# ABOUTME: A key present with an undef value is the case that separates them.

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

# `exists` IS [container, key, memory]. Measured on `exists($h{a})`:
#
#     8 Exists in=[5, 6, 7]  stamp=Boolean    5 = HashLiteral %h
#
# the memory last, ordering the question against stores.
#
# MEMBERSHIP IS NOT DEFINEDNESS, which is the node's whole reason for
# existing -- its ABOUTME records the miscompile that created it. A key
# present with an UNDEF value is the only case that separates the two, so it
# is asserted first.
subtest 'exists asks membership' => sub {
    round_trips(<<'SRC', 'a present key whose value is undef');
my %h = (a => 1, u => undef);
print exists($h{u}) ? "e" : "-";
print defined($h{u}) ? "d" : "-";
print exists($h{zz}) ? "e" : "-";
print "\n";
SRC

    round_trips(<<'SRC', 'over an array');
my @a = (1, 2);
print exists($a[1]) ? "e" : "-";
print exists($a[9]) ? "e" : "-";
print "\n";
SRC
};

# IT OBSERVES STORES, which is what the memory edge is for: a key added after
# the literal was built must be visible.
subtest 'exists observes a later store' => sub {
    round_trips(<<'SRC', 'a key added after construction');
my %h = (a => 1);
print exists($h{b}) ? "e" : "-";
$h{b} = 2;
print exists($h{b}) ? "e" : "-";
print "\n";
SRC
};

# AND A DELETE REMOVES IT -- the same question from the other side, and the
# pair is what makes either meaningful.
subtest 'delete then exists' => sub {
    round_trips(<<'SRC', 'a deleted key is gone');
my %h = (a => 1, b => 2);
print exists($h{a}) ? "e" : "-";
delete $h{a};
print exists($h{a}) ? "e" : "-";
print exists($h{b}) ? "e" : "-";
print "\n";
SRC
};

done_testing;
