# ABOUTME: `my @a` / `my %h` in a loop body is a fresh aggregate every iteration:
# ABOUTME: the declaration is pinned where it runs, not hoisted above the loop.

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

# THE GRAPH HAD NO NODE FOR "declare @a HERE": the literal is the aggregate,
# with no control input, so the renderer declared it once in the prologue and
# every iteration after the first saw the last one's writes. Measured:
# perl 6;7;8; -- emitted 6;8;11;.
round_trips(<<'SRC', 'an array declared in a foreach body');
my $s = ""; for my $i (1..3) { my @a = (5); $a[0] += $i; $s .= "$a[0];" } print "$s\n";
SRC

round_trips(<<'SRC', 'a hash declared in a foreach body');
my $s = ""; for my $i (1..3) { my %h = (k => 5); $h{k} += $i; $s .= "$h{k};" } print "$s\n";
SRC

round_trips(<<'SRC', 'an empty array declared in a foreach body');
my $s = ""; for my $i (1..3) { my @a; push @a, $i; $s .= scalar(@a) . ";" } print "$s\n";
SRC

round_trips(<<'SRC', 'an array declared in a while body');
my $s = ""; my $i = 0; while ($i < 3) { $i++; my @a = (5); $a[0] += $i; $s .= "$a[0];" } print "$s\n";
SRC

round_trips(<<'SRC', 'an array declared in a loop inside a sub');
sub f { my $s = ""; for my $i (@_) { my @a = (5); $a[0] += $i; $s .= "$a[0];" } $s }
print f(1, 2, 3), "\n";
SRC

# A LIST ASSIGN OF UNKNOWN ARITY IN A LOOP BODY stays an Assign node, and
# with no control input it was placed by the prologue rules -- above the
# inner loop whose induction variable it reads (chalk's BNF/Target/C.pm:
# `$phi127` used before its declaration).
round_trips(<<'SRC', 'a list assign from a deref in a nested loop body');
my @g = ([[1, 2], [3, 4]], [[5, 6]]); my $s = "";
for my $preds (@g) { for my $pair (@$preds) { my ($a, $b) = @$pair; $s .= "$a$b;" } }
print "$s\n";
SRC

# OUTSIDE A LOOP the prologue placement is right and stays.
round_trips(<<'SRC', 'an array declared outside any loop');
my @a = (5); $a[0] += 1; print "$a[0]\n";
SRC

done_testing;
