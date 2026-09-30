# ABOUTME: A `use` under `package X` imports into X, and `use parent` sets
# ABOUTME: X's @ISA -- so a phase block is emitted in the package it ran in.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);
mkdir "$dir/orig";
mkdir "$dir/emit";

sub write_file ($path, $text) {
    open my $fh, '>', $path or die $!; print $fh $text; close $fh;
}

write_file("$dir/orig/Base.pm", "package Base;\nsub hello { 'hi from ' . ref(\$_[0]) }\n1;\n");
write_file("$dir/emit/Base.pm", "package Base;\nsub hello { 'hi from ' . ref(\$_[0]) }\n1;\n");

# THE MODULE chalk's ElaboratedContext is: a package, a `use parent`, and
# nothing else. The emission ran the parent import from `main`, so it set
# @main::ISA and Kid inherited nothing.
my $kid = <<'PM';
package Kid;
use 5.42.0;
use parent -norequire, 'Base';
use List::Util qw(sum);
sub total { sum(@_) }
PM
write_file("$dir/orig/Kid.pm", $kid);
write_file("$dir/kid.pl", $kid);
my $json = qx($^X -Ilib -I$dir/orig -MO=-q,SoN,json,not_package=SoN $dir/kid.pl 2>$dir/err);
my $d = SoN::Deparse->new;
my $out = $d->render(JSON::PP->new->utf8->decode($json));
ok defined $out, 'it renders' or diag $d->gap;
like $out // '', qr/^package Kid;$/m, 'the phase blocks run in their package';
write_file("$dir/emit/Kid.pm", $out // '');

my $probe = q{-e 'use Base; use Kid; print Kid->hello, " ", Kid::total(1, 2, 3), "\n"'};
is scalar qx($^X -I$dir/emit $probe 2>&1), scalar qx($^X -I$dir/orig $probe 2>&1),
    'the emitted module inherits and imports where the source did'
    or diag $out;

done_testing;
