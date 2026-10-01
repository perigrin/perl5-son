# ABOUTME: A subclass's own fields keep their real field index and name: perl numbers
# ABOUTME: fields across the parent chain, so a child's first field is not index 0.

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

# THE CLASS RECORD NUMBERED A SUBCLASS'S FIELDS FROM 0. perl gives C's
# first field the index after P's, so the record named it `$field0` (no
# name at index 0) and every FieldAccess into it refused -- "a FieldAccess
# to a field the class record does not name", 19 of chalk's lib/ modules.
round_trips(<<'SRC', 'a subclass reads its own field and its parent\'s');
use v5.42; use experimental 'class';
class P { field $a = 1; method a { $a } }
class C :isa(P) { field $b = 2; method b { $b } }
my $o = C->new; print $o->a, $o->b, "\n";
SRC

round_trips(<<'SRC', 'a subclass :param field and a default');
use v5.42; use experimental 'class';
class P { field $x :param; method x { $x } }
class C :isa(P) { field $y :param = 5; field @l = (7); method y { $y . $l[0] } }
my $o = C->new(x => 1, y => 2); print $o->x, $o->y, C->new(x => 3)->y, "\n";
SRC

round_trips(<<'SRC', 'three levels');
use v5.42; use experimental 'class';
class K1 { field $a = "a"; method a { $a } }
class K2 :isa(K1) { field $b = "b"; method b { $b } }
class K3 :isa(K2) { field $c = "c"; method c { $c } }
my $o = K3->new; print $o->a, $o->b, $o->c, "\n";
SRC

done_testing;
