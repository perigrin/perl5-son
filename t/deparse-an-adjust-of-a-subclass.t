# ABOUTME: A subclass keeps its own ADJUST blocks whether or not its parent has any: the
# ABOUTME: count of the parent's blocks is a count, not the last block a list returned.

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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
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

# `adjust_cvs` RETURNS A LIST. In scalar context it gave the parent's LAST
# block, a code reference, which numified to its address: the range of the
# child's own blocks was empty and every one was dropped -- no warning, and
# the object came back built without them. perl 12, emitted 10.
round_trips(<<'SRC', "a child's ADJUST when the parent has one");
use v5.42; use experimental 'class';
class P { field $n :reader = 0; ADJUST { $n = 1 } }
class K :isa(P) { field $m :reader = 0; ADJUST { $m = 2 } }
my $o = K->new; print $o->n, $o->m, "\n";
SRC

# A parent with NO blocks returned the empty list: undef, and a warning.
round_trips(<<'SRC', "a child's ADJUST when the parent has none");
use v5.42; use experimental 'class';
class P { field $n :reader = 0; }
class K :isa(P) { field $m :reader = 0; ADJUST { $m = 2 } }
my $o = K->new; print $o->n, $o->m, "\n";
SRC

round_trips(<<'SRC', "two ADJUSTs on each side");
use v5.42; use experimental 'class';
class P { field $s :reader = ""; ADJUST { $s .= "a" } ADJUST { $s .= "b" } method add($x) { $s .= $x; return } }
class K :isa(P) { ADJUST { $self->add("c") } ADJUST { $self->add("d") } }
print K->new->s, "\n";
SRC

done_testing;
