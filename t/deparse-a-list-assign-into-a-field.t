# ABOUTME: A list assignment into a class field aggregate -- `%h = ...`, `@a = ...` -- is a
# ABOUTME: store on the chain, not a floating node nothing reaches.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

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


# THE ASSIGN WAS BUILT AND LEFT FLOATING: only a demoted lexical or a store
# through a reference was put on the chain, so nothing reached a store into a
# field aggregate and the statement vanished. chalk's Chalk::MOP is
# `%graph_registry = $graphs->%*` -- the registry stayed empty, and the tests
# that read it back failed. perl 2, emitted 0.
round_trips(<<'SRC', 'a hash field from a dereference');
use v5.42; use experimental 'class';
class R { field %h; method set($r) { %h = $r->%*; return $self } method n { return scalar(keys %h) } }
print R->new->set({a => 1, b => 2})->n, "\n";
SRC

round_trips(<<'SRC', 'an array field from a slurpy parameter');
use v5.42; use experimental 'class';
class R { field @a; method set(@v) { @a = @v; return $self } method n { return scalar(@a) } }
print R->new->set(1, 2, 3)->n, "\n";
SRC

round_trips(<<'SRC', 'an array field from a list');
use v5.42; use experimental 'class';
class R { field @a; method set($x) { @a = ($x, $x + 1); return $self } method n { return "@a" } }
print R->new->set(4)->n, "\n";
SRC

round_trips(<<'SRC', 'a field cleared');
use v5.42; use experimental 'class';
class R { field @a = (1, 2); method clear { @a = (); return $self } method n { return scalar(@a) } }
print R->new->n, R->new->clear->n, "\n";
SRC

# A METHOD ENDING IN A WHOLE-FIELD ASSIGNMENT returns its value, and the
# renderer had no rule for an Assign whose target is a field: chalk's
# Earley::reset_parse_state (`@_errors = ()`) and EmitHelpers'
# `%_class_scope_vars = ()` refused their whole modules.
round_trips(<<'SRC', 'a method that ends by clearing its field aggregates');
use v5.42; use experimental 'class';
class K { field %h = (a => 1, b => 2); field @l = (1, 2, 3);
  method reset_h { %h = () } method reset_l { @l = (9) } method n { scalar(keys %h) . scalar(@l) } }
my $k = K->new; my $a = $k->reset_h; my @b = $k->reset_l; print $a, scalar(@b), $k->n, "\n";
SRC

done_testing;
