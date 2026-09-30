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
    # STDOUT ONLY: the emission runs under warnings the source may not.
    my $out = qx($^X $f 2>/dev/null); unlink $f; return $out;
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

# THE CALL'S ARGUMENTS ARE WHAT PERL ALREADY RESOLVED, and checking them
# again against the declared prototype can refuse them at COMPILE time. A
# call that bypassed the prototype in the source -- `&f(1)` -- carries one
# argument, and `f(1)` under `($$)` is "Not enough arguments": perl's own
# comp/uproto.t went from DIFFERS to EMITS_INVALID_PERL on exactly that once
# headers declared prototypes. A prototyped callee is called with `&`.
round_trips(<<'SRC', 'a call that bypassed the prototype still bypasses it');
sub f ($$) { scalar(@_) . " [@_]" }
print &f(1), "\n";
print f(1, 2), "\n";
SRC

round_trips(<<'SRC', 'no prototype stays undeclared');
sub g { 1 }
print defined(prototype \&g) ? "def" : "undef", "\n";
SRC

round_trips(<<'SRC', 'an empty prototype');
sub PI () { 3 }
print "[", prototype(\&PI), "]\n";
SRC

# A PROTOTYPE UNDER `use v5.36`, WHERE SIGNATURES ARE ON. There `sub g ($)`
# is a SIGNATURE, not a prototype, so the emission's `($)` parsed as one and
# the program did not compile: corpus 008, which turns signatures off only
# around that one sub. `:prototype(...)` means a prototype under any bundle.
round_trips(<<'SRC', 'a prototype where signatures are on');
use v5.36;
no feature "signatures";
sub g ($) { return "g[" . $_[0] . "]" }
use feature "signatures";
print g 1, 2;
print "\n";
SRC

done_testing;
