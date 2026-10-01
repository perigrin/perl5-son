# ABOUTME: A method or reader whose NAME matches a boolean wire field -- is_param,
# ABOUTME: has_default -- keeps its graph key; only the flag fields become booleans.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub wire_of ($src) {
    my $f = "$dir/w." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return JSON::PP->new->utf8->decode($j);
}

# THE BOOLEAN RULE IS KEYED ON THE FIELD NAME, and it applied at every depth
# -- so inside a class's `methods` map, keyed by METHOD name, a method called
# `is_param` became `true` instead of `K::is_param`. The renderer then found
# no graph for it: "no Start node" (chalk's MOP/Field.pm and others).
my $w = wire_of(<<'SRC');
use v5.42; use experimental 'class';
class K { field $has_default :param :reader = 0; method is_param { 1 } method invocant { 2 } }
SRC
my $m = $w->{classes}{K}{methods};
is $m->{has_default}, 'K::has_default', 'a reader named like a flag keeps its graph key';
is $m->{is_param},    'K::is_param',    'a method named like a flag keeps its graph key';
is $m->{invocant},    'K::invocant',    '... another flag name';

# THE FLAGS THEMSELVES ARE STILL BOOLEANS.
my ($f) = grep { $_->{name} eq '$has_default' } $w->{classes}{K}{fields}->@*;
ok JSON::PP::is_bool($f->{is_param}), 'a field record\'s is_param is still a boolean';
ok JSON::PP::is_bool($w->{classes}{K}{is_class}), '... and is_class';

done_testing;
