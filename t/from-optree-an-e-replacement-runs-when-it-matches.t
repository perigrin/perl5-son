# ABOUTME: A s///e replacement runs only when its pattern matches, and what it
# ABOUTME: does -- an increment, a string eval (s///ee) -- is kept, not dropped.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>$dir/err);
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

# THE REPLACEMENT'S EFFECTS WERE DROPPED. It was walked on a snapshot of the
# stack machine and only its value came back, so `$n++` printed `a2c 2` where
# perl prints `a2c 3`. Nothing refused: a silent miscompile.
round_trips(<<'SRC', 'an increment in the replacement');
my $s = "abc";
my $n = 2;
$s =~ s/b/$n++/e;
print "$s $n\n";
SRC

# AND ONLY WHEN IT MATCHES: no match, no replacement, no increment.
round_trips(<<'SRC', 'an increment in a replacement whose pattern misses');
my $s = "xyz";
my $n = 2;
$s =~ s/b/$n++/e;
print "$s $n\n";
SRC

# s///ee IS `s/.../eval(EXPR)/e`: the string eval's Coerce was pinned to the
# snapshot's control and left hanging, "a control node with 2 successors".
# Corpus 100 and 015.
round_trips(<<'SRC', 'a string eval in the replacement (s///ee)');
my $s = "abc";
my $c = q{3*4};
$s =~ s/b/$c/ee;
print "$s\n";
SRC

round_trips(<<'SRC', 'a replacement that reads its own capture and writes');
my $s = "a5c";
my $t = "";
$s =~ s/(\d)/$t = "saw $1"; $1 * 2/e;
print "$s $t\n";
SRC

round_trips(<<'SRC', 'a pure replacement is unchanged');
my $s = "abc";
my $n = 2;
$s =~ s/b/$n + 1/e;
print "$s\n";
SRC

# THE SAME TRAP IN ANY ARM. A string eval closes over a one-input Region, and
# the arm-identity walk stopped there, so an if/else whose arm evals had no
# predecessors for its join: "a join Phi with 2 inputs and 0 predecessors".
round_trips(<<'SRC', 'a string eval inside an if arm');
my $c = q{3*4};
my $x = 1;
if ($ENV{HOME}) { $x = eval $c }
print "$x\n";
SRC

done_testing;
