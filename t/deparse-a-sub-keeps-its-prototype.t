# ABOUTME: A named sub's prototype reaches the wire with its metadata and the
# ABOUTME: emission declares it, so prototype() and parsing agree with the source.

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

# THE WIRE HAD NO PLACE FOR IT. A method entry carries nodes, start and
# returns; the sub metadata carries the signature -- and a prototype is
# neither. The emission declared `sub f {` and perl's prototype() said "".
# Corpus 063.
round_trips(<<'SRC', 'prototype() reads what the source declared');
sub f ($) { 1 }
my $p = prototype \&f;
print "[$p]\n";
SRC

# A PROTOTYPE IS NOT DECORATIVE: it changes how the CALL parses. `($)` makes
# `one 1, 2` pass one argument and leave 2 in the enclosing list.
round_trips(<<'SRC', 'a ($) prototype changes how a call parses');
sub one ($) { "[" . $_[0] . "]" }
my @r = (one 1, 2);
print scalar(@r), " @r\n";
SRC

round_trips(<<'SRC', 'no prototype stays undeclared');
sub g { 1 }
print defined(prototype \&g) ? "def" : "undef", "\n";
SRC

round_trips(<<'SRC', 'an empty prototype');
sub PI () { 3 }
print "[", prototype(\&PI), "]\n";
SRC

done_testing;
