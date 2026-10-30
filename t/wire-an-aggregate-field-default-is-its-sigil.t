# ABOUTME: a `%` or `@` field with a computed default is a Hash or an Array on the wire,
# ABOUTME: whatever list its default's graph returns.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub classes_of ($src) {
    my $f = "$dir/c." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f;
    return decode_json($out)->{classes};
}

# `field %items = (r => { 7 => "V" }, s => [1, 2])` was typed List, the type of
# its default's graph, and a consumer read %items as a list (pvm 153: chalk's
# "Subscript container has repr=List").
my $c = classes_of(q{use v5.42; use experimental 'class';
    class K { field %items = (r => { 7 => "V" }, s => [1, 2]); field @l = (1, [2]); field $x = [3];
              method g { scalar(keys %items) . scalar(@l) . ref($x) } }
    print K->new->g, "\n";});
my %type = map { $_->{name} => $_->{type} } $c->{K}{fields}->@*;
is($type{'%items'}, 'Hash',  'a % field with a computed default is a Hash');
is($type{'@l'},     'Array', 'an @ field with a computed default is an Array');
is($type{'$x'},     'ArrayRef', 'a $ field keeps its default graph\'s type');

done_testing;
