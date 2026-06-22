# ABOUTME: Tests that B::SoN emits a declarative `classes` JSON section.
# ABOUTME: Class structure (name, parent, fields, methods) replayed Chalk-side as a MOP.

use v5.42.0;
use Test2::V0;
use JSON::PP ();

my $perl = $^X;
my $lib  = 'lib';

# Run B::SoN,json on a source file and return the decoded JSON.
sub son_json ($source) {
    my ($fh, $tmp);
    require File::Temp;
    ($fh, $tmp) = File::Temp::tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $source;
    close $fh;
    my $out = `$perl -I$lib -MO=SoN,json,package=Counter $tmp 2>/dev/null`;
    return JSON::PP->new->decode($out);
}

my $SRC = <<'PERL';
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param;
    method val { $n }
    method bump { $n }
}
PERL

my $data = son_json($SRC);

subtest 'emits a classes section' => sub {
    ok(exists $data->{classes}, 'JSON has a top-level classes section');
    ok(exists $data->{classes}{Counter}, 'Counter class is present');
};

subtest 'class carries name, parent, fields, methods' => sub {
    my $c = $data->{classes}{Counter};
    is($c->{name}, 'Counter', 'class name');
    ok(!defined $c->{parent} || $c->{parent} eq '', 'no parent (not :isa)');

    my @fields = ($c->{fields} // [])->@*;
    is(scalar @fields, 1, 'one field');
    is($fields[0]{name}, '$n', 'field name');
    is($fields[0]{fieldix}, 0, 'field index 0');
    ok($fields[0]{is_param}, 'field is :param');
    is($fields[0]{param_name}, 'n', 'param name');

    my $methods = $c->{methods} // {};
    ok(exists $methods->{val},  'method val present');
    ok(exists $methods->{bump}, 'method bump present');
    # Method values reference the per-method graph keys in the methods section.
    ok(exists $data->{methods}{ $methods->{val} },
        'val method-ref points at a real graph');
};

subtest 'parent is recorded for an :isa class' => sub {
    my $isa_src = <<'PERL';
use feature 'class';
no warnings 'experimental::class';
class Base { method kind { 1 } }
class Counter :isa(Base) { method kind2 { 2 } }
PERL
    my $d = son_json($isa_src);
    is($d->{classes}{Counter}{parent}, 'Base', 'Counter :isa(Base) records parent');
};

done_testing();
