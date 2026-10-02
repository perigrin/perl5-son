# ABOUTME: Every emission opens with the version bundle we target, strict and
# ABOUTME: warnings included; a source `use VERSION` at or below it is subsumed.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);
mkdir "$dir/orig";
mkdir "$dir/emit";

sub emit_file ($src, $path) {
    my $f = "$dir/src." . int(rand 1e9);
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    my $d = SoN::Deparse->new;
    my $out = $d->render(JSON::PP->new->utf8->decode($j));
    diag $d->gap unless defined $out;
    open my $o, '>', $path or die $!; print $o $out // ''; close $o;
    return $out;
}

# A MODULE THAT RETURNS NOTHING. `use v5.42.0` turns on module_true, so a
# file ending in a class -- 169 of chalk's 179 modules -- needs no `1;`.
# The emission spelled the BEGIN block as `require(5.042)`, which checks the
# version and drops the bundle: "Mod.pm did not return a true value".
my $mod = <<'PM';
use v5.42.0;
package Mod;
sub answer { 42 }
PM
open my $pm, '>', "$dir/orig/Mod.pm" or die $!; print $pm $mod; close $pm;
my $out = emit_file($mod, "$dir/emit/Mod.pm");
like $out, qr/\Ause 5\.42\.0;\n/, 'the emission opens with the target bundle';
unlike $out, qr/require\(5\.0|^use 5\.042;/m, '... which subsumes the source\'s own';
is scalar qx($^X -I$dir/emit -e 'use Mod; print Mod::answer()' 2>&1),
   scalar qx($^X -I$dir/orig -e 'use Mod; print Mod::answer()' 2>&1),
   'the emitted module loads without a true value, as the source does';

# A PROGRAM THAT DECLARED NO VERSION, or an older one, gets the bundle too:
# the emission is modern Perl whatever the source was written against.
my $prog = emit_file(<<'SRC', "$dir/p.pl");
use 5.036;
print "ok\n";
SRC
like $prog, qr/\Ause 5\.42\.0;\n/, 'an older version is raised to the target';
unlike $prog, qr/require\(5\.0|^use 5\.036;/m, '... not kept beside it';
my $bare = emit_file("print 'hi';\n", "$dir/b.pl");
like $bare, qr/\Ause 5\.42\.0;\n/, 'a program with no version gets the bundle';

# THE BUNDLE PUTS THE SOURCE UNDER `source::encoding "ascii"`, so a string
# holding a non-ASCII character must be spelled by code point, not raw.
my $wide = emit_file(q{my $s = "caf\x{e9} \x{663}"; print length($s), "\n";} . "\n",
                     "$dir/w.pl");
unlike $wide, qr/[^\x00-\x7f]/, 'the emission is pure ASCII';
is scalar qx($^X $dir/w.pl 2>&1), "6\n", '... and the string is the same six characters';

done_testing;
