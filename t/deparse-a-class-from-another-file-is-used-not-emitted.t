# ABOUTME: A class the program `use`s from another file is described on the wire
# ABOUTME: but not emitted: the emission loads it as the source did.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);
mkdir "$dir/lib";

# THE PARENT LIVES IN ITS OWN FILE, as every class in chalk's lib/ does.
open my $pm, '>', "$dir/lib/Animal.pm" or die $!;
print $pm <<'PM';
use v5.42.0;
use experimental 'class';
class Animal {
    field $name :param;
    method name { $name }
    method speak { $self->name . " makes a sound" }
}
1;
PM
close $pm;

# AN EMPTY CLASS HAS NO SUB OF ITS OWN to say where it came from; its file
# being one the program loaded is the evidence.
open my $pm2, '>', "$dir/lib/Blank.pm" or die $!;
print $pm2 "use v5.42.0;\nuse experimental 'class';\nclass Blank {}\n1;\n";
close $pm2;

my $src = <<'SRC';
use v5.42.0;
use experimental 'class';
use Animal;
use Blank;
class Dog :isa(Animal) {
    method speak { $self->name . " barks" }
}
print Dog->new(name => "Rex")->speak, "\n";
print Animal->new(name => "Cat")->speak, "\n";
print ref(Blank->new), "\n";
SRC

sub run_perl ($code) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $code; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X -I$dir/lib $f 2>&1); unlink $f;
    return $out;
}

my $f = "$dir/prog.pl";
open my $fh, '>', $f or die $!; print $fh $src; close $fh;
my $json = qx($^X -Ilib -I$dir/lib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
my $data = JSON::PP->new->decode($json);

# THE WIRE STILL DESCRIBES THE PARENT -- a consumer resolving Dog's methods
# needs Animal's shape -- but says it is not this file's to emit.
ok $data->{classes}{Animal}, 'the parent class is on the wire';
ok $data->{classes}{Animal}{external}, '... marked external: its code is another file';
ok !$data->{classes}{Dog}{external}, 'the class defined here is not';
ok !$data->{classes}{Blank} || $data->{classes}{Blank}{external},
    'an empty class from another file is not ours either';

# THE EMISSION: it rendered Animal's methods, whose graphs were never
# translated (they are in Animal.pm), and refused "no Start node".
my $d = SoN::Deparse->new;
my $out = $d->render($data);
ok defined $out, 'it renders' or diag $d->gap;
unlike $out // '', qr/^\s*class (?:Animal|Blank)\b/m,
    'neither loaded class is re-declared';
is run_perl($out // ''), run_perl($src), 'and it runs as the source does'
    or diag $out;

# AN EMPTY CLASS DECLARED HERE IS OURS. chalk's Chalk::IR::Value is
# `class Chalk::IR::Value :isa(Chalk::IR::Node) {}` -- no sub of its own, so
# nothing said it came from this file, and it was not emitted at all. A
# subclass loaded on top of the emission then declared `:isa` of a package
# that is not a class, and perl segfaulted (61 of chalk's lib/ modules).
my $marker = "$dir/lib/Marker.pm";
my $msrc = <<'PM';
use v5.42.0;
use experimental 'class';
use Animal;
class Marker :isa(Animal) {}
PM
my $mf = "$dir/marker.pl";
open my $mh, '>', $mf or die $!; print $mh $msrc; close $mh;
my $mjson = qx($^X -Ilib -I$dir/lib -MO=-q,SoN,json,not_package=SoN $mf 2>$dir/err);
my $mdata = JSON::PP->new->utf8->decode($mjson);
ok $mdata->{classes}{Marker} && !$mdata->{classes}{Marker}{external},
    'an empty class declared here is on the wire as ours';
my $mout = SoN::Deparse->new->render($mdata) // '';
like $mout, qr/^\s*class Marker :isa\(Animal\)/m, '... and emitted';
open my $mo, '>', $marker or die $!; print $mo $mout; close $mo;
is scalar qx($^X -I$dir/lib -e 'use Marker; print ref(Marker->new(name => "x")), "\n"' 2>&1),
   "Marker\n", '... so a program loading it gets the class';

done_testing;
