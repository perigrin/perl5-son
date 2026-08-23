# ABOUTME: Tests the not_package= exclusion filter, which keeps user packages by default.
# ABOUTME: An inclusion filter drops a package it was not told about; exclusion keeps it.

use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use JSON::PP;

# The `package=` filter is INCLUSION: it emits only the packages it is told
# about. That is correct for a harness that knows its input's shape (a corpus
# case, whose classes are parsed out of the source), and WRONG for one that
# consumes arbitrary real files -- anything it was not told about vanishes with
# no diagnostic, and a call into the vanished package then arrives with no
# resolved callee and no return type.
#
# `not_package=` is the complement: emit everything EXCEPT the named prefixes.
# It fails toward NOISE (an unanticipated internal leaks into the wire) rather
# than toward SILENCE (an unanticipated user package disappears), which is the
# right direction for a filter over input whose shape is not known in advance.

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire_for ($src, $name, @opts) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} $src;
    close $fh;
    my $opts = join(',', 'json', @opts);
    my $json = qx{$PERL -Ilib -MO=SoN,$opts $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

my $TWO_PKG = <<'PL';
use 5.42.0;
package Thing { sub greet { 7 } }
package main;
print Thing::greet(), "\n";
PL

subtest 'the inclusion filter drops an unnamed package (the defect)' => sub {
    my $wire = wire_for($TWO_PKG, 'incl', 'package=main');
    my $classes = $wire->{classes} // {};
    ok !exists $classes->{Thing},
        'package=main drops Thing -- this is the behaviour being fixed';
};

subtest 'the exclusion filter keeps it' => sub {
    my $wire = wire_for($TWO_PKG, 'excl', 'not_package=SoN::');
    my $classes = $wire->{classes} // {};
    my $methods = $wire->{methods} // {};

    ok exists $classes->{Thing}, 'Thing survives an exclusion filter';

    # `main` is asserted through `methods`, not `classes`. Measured: main never
    # appears as a class under ANY option, including no filter at all -- the
    # file's top-level statements are emitted as the method main::__PROGRAM__.
    # An earlier version of this test asserted $classes->{main} and failed
    # against correct behaviour.
    ok exists $methods->{'main::__PROGRAM__'},
        'the top-level program survives too';

    # The whole reason a filter exists: without one, every loaded producer
    # internal leaks into the wire.
    my @son = grep { /^SoN::/ } sort keys %$classes;
    is scalar @son, 0, 'no SoN:: internals leak through';
};

subtest 'multiple exclusions compose' => sub {
    my $wire = wire_for($TWO_PKG, 'multi',
        'not_package=SoN::', 'not_package=Thing');
    my $classes = $wire->{classes} // {};
    my $methods = $wire->{methods} // {};

    ok !exists $classes->{Thing}, 'an explicitly excluded package is dropped';
    ok exists $methods->{'main::__PROGRAM__'},
        'and unrelated packages are unaffected';
};

subtest 'exclusion is by PREFIX, not exact match' => sub {
    # `package=` is documented as exact match. Exclusion must be a prefix test
    # or it cannot express "drop the SoN:: tree", which is the entire use case
    # -- there are ~90 such classes and naming each is not maintainable.
    my $wire = wire_for($TWO_PKG, 'prefix', 'not_package=SoN::');
    my $classes = $wire->{classes} // {};
    ok !exists $classes->{'SoN::IR::Node'},
        'a nested SoN:: class is excluded by the prefix';
    ok !exists $classes->{'SoN::FromOptree'},
        'and so is a differently-nested one';
};

subtest 'a qualified sub declaration is kept, not just `package` statements' => sub {
    # THE CASE A DECLARATION-SCANNING FIX WOULD MISS. t/base/lex.t introduces
    # namespaces via `sub xyz::foo {...}` with no `package` statement anywhere,
    # so a harness that scanned for `^package` and passed package=$_ would
    # still drop these. An exclusion filter never has to know they exist.
    my $src = <<'PL';
use 5.42.0;
sub xyz::foo { "bar" }
package main;
print xyz::foo(), "\n";
PL
    my $wire = wire_for($src, 'qualsub', 'not_package=SoN::');
    my $classes = $wire->{classes} // {};
    ok exists $classes->{xyz},
        'a namespace created only by a qualified sub name survives';
};

subtest 'no filter at all still emits everything' => sub {
    my $wire = wire_for($TWO_PKG, 'nofilter');
    my $classes = $wire->{classes} // {};
    ok exists $classes->{Thing}, 'Thing present with no filter';
    ok((grep { /^SoN::/ } keys %$classes),
        'and the internals leak, which is why a filter is wanted');
};

done_testing;
