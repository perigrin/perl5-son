# ABOUTME: `\($x, $y)` is a list of references, one per item, and `\(@a)` is a
# ABOUTME: reference per ELEMENT; a store through one reaches the variable.

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

# REFGEN HAD ONE INPUT. OpMap gives it `[1, 'Ref', 1, 0]`, so `\($x, $y)`
# built one Ref over the LAST item and left the first on the stack as a bare
# value, and the store through it was lost because _address_taken only saw
# srefgen. Measured:
#
#     emitted   my @r = ($x, \($y));      perl 2 9   ours 2 2
round_trips(<<'SRC', 'a reference per item, and a store through one');
my ($x, $y) = (1, 2);
my @r = \($x, $y);
${$r[1]} = 9;
print scalar(@r), " $x $y\n";
SRC

# `\(@a)` IS THE SPECIAL CASE perlref names: a reference to each ELEMENT,
# not to the array. Corpus 206 (and 009's `${$r[1]}`).
round_trips(<<'SRC', 'a reference per element of an array');
my @a = (10, 20);
my @r = \(@a);
print scalar(@r), " ", ${$r[0]}, " ", ${$r[1]}, "\n";
SRC

round_trips(<<'SRC', 'a store through an element reference reaches the array');
my @a = (10, 20);
my @r = \(@a);
${$r[0]} = 5;
print "@a\n";
SRC

# `\@a` HAD THE SAME HOLE: taking the reference did not mark the array
# mutated, so a later list read took the flatten shortcut and printed the
# array as first constructed. Measured: perl `5 20`, emitted `10 20`.
round_trips(<<'SRC', 'a store through \@a reaches the array');
my @a = (10, 20);
my $r = \@a;
$r->[0] = 5;
print "@a\n";
SRC

# AN AGGREGATE AMONG OTHER ITEMS IS NOT FLATTENED: `\(@a, $b)` is (\@a, \$b).
round_trips(<<'SRC', 'an array among other items is referenced whole');
my @a = (1, 2, 3);
my $b = 4;
my @r = \(@a, $b);
print scalar(@r), " ", ref($r[0]), " ", ref($r[1]), " ", scalar(@{$r[0]}), "\n";
SRC

done_testing;
