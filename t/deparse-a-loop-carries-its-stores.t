# ABOUTME: A store inside a loop body is seen after the loop: the loop carries memory
# ABOUTME: through its header, so a read after it is not the read before it.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    if (!$data || $err =~ /skipped/) {
        fail "$name: translates"; diag $err; return;
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

# THE LOOP CARRIED MEMORY ONLY FOR A STORE ITS SCAN RECOGNISED -- an
# lvalue helem or aelem, or a shift -- found by following ->next from the
# body's start. `$h{a}++` is a multideref, so the body made no memory Phi,
# and the read after the loop was the read at the top of the body: perl's
# 3 printed 2.
round_trips(<<'SRC', 'a hash element incremented in a foreach');
my @a = (1, 2, 3); my %h = (a => 0);
for my $x (@a) { $h{a}++ }
print $h{a}, "\n";
SRC
round_trips(<<'SRC', 'a hash element incremented in a while');
my %h = (n => 0); my $i = 0;
while ($i < 4) { $h{n}++; $i++ }
print "$h{n} $i\n";
SRC
round_trips(<<'SRC', 'a store behind a guard in the body');
my @a = (1, 2, 3, 4); my %h = (odd => 0);
for my $x (@a) { next unless $x % 2; $h{odd} += $x }
print $h{odd}, "\n";
SRC
round_trips(<<'SRC', 'a sub that stores, called in the body');
our %seen;
sub mark { $seen{$_[0]}++ }
for my $x (qw(a b a)) { mark($x) }
print join(",", map { "$_=$seen{$_}" } sort keys %seen), "\n";
SRC

# perl's own base/while.t: a loop that breaks, its value read after it,
# then a second loop over the same package scalar. With the exit carrying
# memory, the read after the first loop was bound at its exit's merge.
round_trips(<<'SRC', 'a breaking loop, a read after it, and a second loop');
$x = 0;
while (1) { $x = $x + 1; last if $x == 3; }
print $x == 3 ? "ok 2\n" : "not ok 2\n";
$x = 0;
while ($x != 3) { $x = $x + 1; }
print "ok 3 $x\n";
SRC

# A BODY THAT RETURNS UNLESS AN ARM WENT ROUND: `if (C) { ...; next }
# return;`. The return's path was left as the body's end, and joined the
# latch beside the `next` -- one Proj with two successors, refused by the
# renderer. chalk's EmitHelpers::_find_exists_delete_in_chain.
round_trips(<<'SRC', 'a body that goes round in an arm, and returns after it');
use v5.42;
sub find ($n) {
    my $cur = $n;
    while (defined $cur) {
        if (ref $cur eq 'ARRAY') { return $cur->[0] eq 'x' ? 'found' : 'other' }
        if (ref $cur eq 'HASH') { $cur = $cur->{next}; next; }
        return 'stop';
    }
    return 'end';
}
print find({ next => { next => ['x'] } }), " ", find({ next => \1 }), " ", find({ next => undef }), "\n";
SRC

# A READ AT THE TOP OF A PASS, OF A VARIABLE THE PASS THEN STORES, is the
# value before the store. A variable passed to a call lives in memory, and
# the read was spelled where its value was used -- after `$pos++` -- so each
# pass read the next character (`=1;` for `x=1;`, at base too). It is bound
# at the top of each pass. chalk's Earley::_run_parse steps `$pos` so.
round_trips(<<'SRC', 'a read at the top of a pass, stored later in it');
sub g { $_[1] + 2 }
sub run { my ($in) = @_; my $pos = 0; my $out = ""; while ($pos < length $in) { my $c = substr($in, $pos, 1); if ($c eq "@") { $pos = g($in, $pos); next } $out .= $c; $pos++ } return $out }
print run("ab\@xcd"), "\n";
SRC

# AN IF WHOSE ARMS BOTH END IN `last` meets only past a region that feeds
# the loop's exit. Taken for the join, the walk ran on from it through the
# exit -- the code after the loop was spelled inside the body, and the arm
# that `next`s fell into it (chalk's Earley::_run_parse error recovery).
round_trips(<<'SRC', 'an if in a loop whose arms both leave, one by next first');
sub run { my ($in, $lim) = @_; my $pos = 0; my @err; my $out = "";
  while ($pos < length $in) {
    my $c = substr($in, $pos, 1);
    if ($c eq "@") {
      if (@err < $lim) { push @err, $pos; if ($pos + 2 < length $in) { $pos += 2; next } }
      last;
    }
    $out .= $c; $pos++;
  }
  $out .= "#";
  return "$out|@err" }
print run("ab\@xcd\@yz", 5), " ", run("ab\@xcd", 0), " ", run("ab\@x", 5), "\n";
SRC

# AN ARM THAT RUNS A LOOP OF ITS OWN BEFORE ITS `next`: the search for the
# arm's edge stopped at the inner loop's exit, so the `next` was not seen,
# the arm fell into the `last` after it, and the outer loop ended early.
round_trips(<<'SRC', 'an arm that loops before it nexts, beside a last');
sub run { my ($in) = @_; my $pos = 0; my @err; my $out = "";
  while ($pos < length $in) {
    my $c = substr($in, $pos, 1);
    if ($c eq "@") {
      if (@err < 5) { push @err, $pos; my $s = $pos + 2; if ($s < length $in) { for my $k (1 .. 2) { $out .= "<$k>" } $pos = $s; next } }
      last;
    }
    $out .= $c; $pos++;
  }
  return "$out|@err" }
print run("ab\@xcd\@yz"), " ", run("ab\@x"), "\n";
SRC

done_testing;
