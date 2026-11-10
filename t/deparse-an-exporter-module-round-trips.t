# ABOUTME: a module built on Exporter, which the program `use`s with an import list,
# ABOUTME: is followed onto the wire and the emission still loads and imports it.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);
mkdir "$dir/lib";
sub write_file ($path, $text) { open my $fh, '>', $path or die $!; print $fh $text; close $fh }

write_file( "$dir/lib/ExMod.pm", <<'PM' );
package ExMod;
use Exporter 'import';
our @EXPORT_OK = qw(twice);
sub twice { return $_[0] * 2 }
1;
PM
my $src = "use lib '$dir/lib';\nuse ExMod qw(twice);\nprint twice(21), \"\\n\";\n";
write_file( "$dir/p.pl", $src );

my $json = qx($^X -Ilib -MO=-q,SoN,json $dir/p.pl 2>$dir/err);
my $w = JSON::PP->new->decode($json);
my %mod = map { $_->{name} => 1 } @{ $w->{modules} // [] };
ok $mod{ExMod},    'the module is followed';
ok $mod{Exporter}, '... and Exporter, which it uses';
is $w->{methods}{'ExMod::twice'}{module}, 'ExMod', 'its sub is on the wire, marked as its module\'s';

my $d   = SoN::Deparse->new;
my $out = $d->render($w);
ok defined $out, 'it renders' or diag $d->gap;
unlike $out // '', qr/sub\s+(?:ExMod::)?twice\b/, 'the module\'s sub is not re-emitted';
write_file( "$dir/e.pl", $out // '' );
is scalar qx($^X $dir/e.pl 2>&1), scalar qx($^X $dir/p.pl 2>&1), 'the emission runs as the source does'
    or diag $out;

done_testing;
