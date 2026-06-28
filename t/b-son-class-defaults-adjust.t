# ABOUTME: Tests B::SoN extraction of field defaults and ADJUST blocks (4c-1b).
# ABOUTME: Defaults come from initfields_cv; ADJUST bodies become per-block graph refs.

use v5.42.0;
use Test2::V0;
use JSON::PP ();

my $perl = $^X;
my $lib  = 'lib';

sub son_json ($source, @pkgs) {
    require File::Temp;
    my ($fh, $tmp) = File::Temp::tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $source;
    close $fh;
    my $pkg_opt = join(',', map { "package=$_" } @pkgs);
    my $out = `$perl -I$lib -MO=SoN,json,$pkg_opt $tmp 2>/dev/null`;
    return JSON::PP->new->decode($out);
}

subtest 'a field with an integer default emits its value and type' => sub {
    my $d = son_json(<<'PERL', 'main', 'Counter');
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method val { $n }
}
PERL
    my ($field) = ($d->{classes}{Counter}{fields} // [])->@*;
    ok(defined $field, 'has a field');
    is($field->{name}, '$n', 'field name');
    ok($field->{has_default}, 'field has a default');
    is($field->{type}, 'Int', 'field type inferred from the default (Int)');
    # The default value rides as a graph-ref so the loader can wire the node.
    ok(defined $field->{default_ref}, 'field default_ref present');
    ok(exists $d->{methods}{ $field->{default_ref} },
        'default_ref points at a real graph');
};

subtest 'an ADJUST block is emitted as a graph ref' => sub {
    my $d = son_json(<<'PERL', 'main', 'Box');
use feature 'class';
no warnings 'experimental::class';
class Box {
    field $val :param = 0;
    field $double;
    ADJUST { $double = $val * 2 }
    method double { $double }
}
PERL
    my @adjusts = ($d->{classes}{Box}{adjusts} // [])->@*;
    is(scalar @adjusts, 1, 'Box has one ADJUST block');
    ok(exists $d->{methods}{ $adjusts[0] },
        'the ADJUST graph-ref points at a real graph');
};

done_testing();
