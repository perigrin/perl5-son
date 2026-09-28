# ABOUTME: `substr($s, ...) = X` and 4-argument `substr` write into $s; the
# ABOUTME: write is an ordered store and later reads of $s observe it.

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

# WITH THE PEEPHOLE SUPPRESSED, as B::SoN runs, `substr($a,0,1) = "J"` is
#
#     sassign(const "J", substr[RM](padsv $a, 0, 1))
#
# and sassign's catch-all dropped the substr target: the graph kept a
# 3-input Call that nothing read, and $a stayed the folded constant.
# Corpus 144, and 004's `[$edit]`.
round_trips(<<'SRC', 'an lvalue substr writes its string');
my $a = $ENV{X} // "hello";
substr($a, 0, 1) = "J";
print "[$a]\n";
SRC

# FOUR-ARGUMENT substr WRITES TOO, and yields the old text. Its string was
# not demoted, so the `my` was folded away and the emission read an
# undeclared $b.
round_trips(<<'SRC', 'a 4-argument substr writes and yields the old text');
my $b = $ENV{X} // "hello";
my $old = substr($b, 0, 1, "J");
print "[$b][$old]\n";
SRC

# READS ON BOTH SIDES see the right version.
round_trips(<<'SRC', 'a read before and after the write');
my $s = $ENV{X} // "abc";
my $before = "$s";
substr($s, 1, 1) = "X";
print "$before $s ", index($s, "X"), "\n";
SRC

# THE STALE READ WAS NOT substr'S. Any demoted lexical read before a store
# through a reference was spelled by name at its use, after the store --
# `2 2` for perl's `1 2`. The deparser's stale-read binding covered package
# scalars only; a lexical's store is ordered by control, and can come through
# a reference no name comparison sees.
round_trips(<<'SRC', 'a read before a store through a reference');
my $x = $ENV{X} // 1;
my $r = \$x;
my $before = $x;
$$r = 2;
print "$before $x\n";
SRC

# A READ WHOSE CONSUMER REWRITES IT IN PLACE IS NOT BOUND. tr/// changes
# its subject; binding the subject to a stale temporary transliterated the
# temporary -- corpus 191, `a.c` where perl prints `aZc` -- so only reads
# every consumer of which is known safe are bound.
round_trips(<<'SRC', 'a tr/// subject is rewritten, not a copy of it');
my $s = $ENV{X} // "a.c";
my $t = $s;
my $n = ($t =~ tr/./Z/);
my $u = $s;
$u =~ s/./Z/;
print "$t $n $u\n";
SRC

done_testing;
