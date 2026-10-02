# ABOUTME: A fused string build into a class field -- `$f .= ...`, `$f = "..$x.."` -- is
# ABOUTME: a field store, read before it, in a method and in an ADJUST block alike.

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

# perl FUSES the build and the store into one multiconcat with OPpTARGET_MY,
# and its handler rebound the target as a pad slot. A field is not a pad
# slot: in a method the store vanished (perl xyz, emitted x, no warning), and
# in an ADJUST the append read an unbound slot and the serializer died on the
# undefined input. chalk's Grammar::Node classes append to fields this way.
round_trips(<<'SRC', 'an append to a field in a method');
use v5.42; use experimental 'class';
class P { field $s :reader = "x"; method add($x) { $s .= $x; return } }
my $o = P->new; $o->add("y"); $o->add("z"); print $o->s, "\n";
SRC

round_trips(<<'SRC', 'an append of several parts to a field');
use v5.42; use experimental 'class';
class P { field $s :reader = "x"; method add($x, $y) { $s .= "<$x:$y>"; return } }
my $o = P->new; $o->add(1, 2); $o->add(3, 4); print $o->s, "\n";
SRC

round_trips(<<'SRC', 'an append to a field in an ADJUST');
use v5.42; use experimental 'class';
class P { field $s :reader = ""; ADJUST { $s .= "a" } ADJUST { $s .= "b" } }
print P->new->s, "\n";
SRC

round_trips(<<'SRC', 'an interpolation stored into a field');
use v5.42; use experimental 'class';
class P { field $s :reader = "x"; method set($x) { $s = "<$x>"; return } }
my $o = P->new; $o->set("y"); print $o->s, "\n";
SRC

round_trips(<<'SRC', 'an append whose value is used');
use v5.42; use experimental 'class';
class P { field $s :reader = "x"; method add($x) { my $r = ($s .= $x); return "$r/$s" } }
my $o = P->new; print $o->add("y"), " ", $o->add("z"), "\n";
SRC

done_testing;
