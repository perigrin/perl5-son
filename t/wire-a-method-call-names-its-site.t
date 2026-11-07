# ABOUTME: a method call carries its statement's file and line on the wire, as a
# ABOUTME: may-die divide does: perl's "Can't locate object method" message names them.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
print $fh qq{package C; sub m { 1 }\npackage main;\nmy \$o = \$ENV{X};\n\$o->m;\n};
close $fh;
my $json = qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null);
my @calls;
my $walk; $walk = sub ($x) {
    if (ref $x eq 'HASH') { push @calls, $x if ( $x->{op} // '' ) eq 'Call' && ( $x->{fields}{dispatch_kind} // '' ) eq 'method'; $walk->($_) for values %$x }
    elsif (ref $x eq 'ARRAY') { $walk->($_) for @$x }
};
$walk->(decode_json($json));
is(scalar @calls, 1, 'one method call');
is($calls[0]{fields}{line}, 4, 'it names its line');
is($calls[0]{fields}{file}, $pl, 'and its file');
done_testing;
