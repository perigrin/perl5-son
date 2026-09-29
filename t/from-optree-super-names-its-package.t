# ABOUTME: `$o->SUPER::m()` resolves from the package the call is WRITTEN in;
# ABOUTME: the call carries that package, so the emission can say which.

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
    my $j = qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err);
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

# method_super HAD NO HANDLER, so the Call was named `unknown` and the
# deparser refused. The package is not on the op -- rclass is 0 for it --
# but on the statement that encloses it, and `$o->PKG::SUPER::m()` resolves
# SUPER from PKG wherever it is written. Corpus 050.
round_trips(<<'SRC', 'SUPER at file scope, in a package');
package Base;
sub hi { return "base" }
package Derived;
our @ISA = ("Base");
my $o = bless {}, "Derived";
print $o->SUPER::hi(), "\n";
SRC

# THE CASE THAT MATTERS: the child overrides, so a plain call and SUPER::
# reach different methods -- a lowering that loses the package answers with
# the child's.
round_trips(<<'SRC', 'SUPER from an overriding method');
package Base;
sub hi { return "base" }
package Derived;
our @ISA = ("Base");
sub hi { return "derived" }
sub both { my $s = shift; return $s->SUPER::hi() . "/" . $s->hi() }
package main;
print Derived->both, "\n";
SRC

# A PACKAGE AGGREGATE READ ONLY OUTSIDE THIS GRAPH WAS NEVER STORED. `our
# @ISA = (...)` above, and `our @x` read by a sub: bound as an SSA value,
# the assignment reached the wire only if the program graph read it too.
# Method resolution and other subs read it at runtime.
round_trips(<<'SRC', 'a package array and hash read only by subs');
our @x = (1, 2);
our %h = (a => 1);
sub f { print "@x $h{a}\n" }
f();
SRC

done_testing;
