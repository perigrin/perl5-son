# ABOUTME: A `class` declared with the class feature is emitted as one -- its
# ABOUTME: fields, defaults, ADJUST blocks and methods -- from the wire's classes.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>$dir/err);
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

# THE WIRE HAS HAD THE CLASS FOR A WHILE -- name, parent, fields with their
# default graphs, ADJUST graphs, methods -- and the deparser read none of it.
# The class was never declared, so `Empty->new` died; a method emitted as a
# plain `sub Foo::m` could not see its field, and FieldAccess had no rule at
# all. Corpus 059, 060, 061 and 012's Foo.
round_trips(<<'SRC', 'an empty class');
use feature 'class';
no warnings 'experimental::class';
class Empty {}
print ref(Empty->new), "\n";
SRC

round_trips(<<'SRC', 'a field with a default, read by a method');
use feature 'class';
no warnings 'experimental::class';
class Foo {
    field $x = 5;
    method m { $x }
}
my $o = Foo->new;
print $o->m, "\n";
SRC

round_trips(<<'SRC', 'an ADJUST block writes a field');
use feature 'class';
no warnings 'experimental::class';
class Foo {
    field $x = 1;
    ADJUST { $x = 2 }
    method m { $x }
}
print ref(Foo->new), " ", Foo->new->m, "\n";
SRC

round_trips(<<'SRC', 'a :param field');
use feature 'class';
no warnings 'experimental::class';
class Pt {
    field $x :param = 0;
    field $y :param(why) = 7;
    method sum { $x + $y }
}
print Pt->new(x => 3)->sum, " ", Pt->new(x => 1, why => 1)->sum, "\n";
SRC

done_testing;
