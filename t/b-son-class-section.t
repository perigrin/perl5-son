# ABOUTME: Tests that B::SoN emits a declarative `classes` JSON section.
# ABOUTME: Class structure (name, parent, fields, methods) replayed Chalk-side as a MOP.

use v5.42.0;
use Test2::V0;
use JSON::PP ();

my $perl = $^X;
my $lib  = 'lib';

# Run B::SoN,json on a source file and return the decoded JSON.
sub son_json ($source, $pkg = 'Counter') {
    my ($fh, $tmp);
    require File::Temp;
    ($fh, $tmp) = File::Temp::tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $source;
    close $fh;
    my $out = `$perl -I$lib -MO=SoN,json,package=$pkg $tmp 2>/dev/null`;
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

subtest 'a field with a CUSTOM :param(name) records its VARIABLE name, not the param name (zhi 019f4625)' => sub {
    # `field $left :param(alpha)` -- the field VARIABLE is $left; the constructor
    # PARAM is `alpha`. When no method/ADJUST body references the field, the old
    # code fell back to "$" . param_name = "$alpha" (wrong), which broke :reader
    # detection (the reader CV is named `left`, not `alpha`). The name must come
    # from the class's own field padnames (xhv_class_fields), not the param name.
    my $src = <<'PERL';
use feature 'class';
no warnings 'experimental::class';
class Pair { field $left :param(alpha) :reader; field $right :param(beta) :reader; }
PERL
    my $d = son_json($src, 'Pair');
    my @fields = ($d->{classes}{Pair}{fields} // [])->@*;
    is(scalar @fields, 2, 'two fields');
    my %name_by_ix = map { $_->{fieldix} => $_->{name} } @fields;
    is($name_by_ix{0}, '$left',  'field 0 is $left (variable name, not $alpha)');
    is($name_by_ix{1}, '$right', 'field 1 is $right (variable name, not $beta)');
    my %param_by_ix = map { $_->{fieldix} => $_->{param_name} } @fields;
    is($param_by_ix{0}, 'alpha', 'field 0 param name is still alpha');
    is($param_by_ix{1}, 'beta',  'field 1 param name is still beta');
    # The :reader is detected (the reader CV `left`/`right` matches the field
    # variable name), so it is NOT emitted as a shadowing user-method graph.
    my %methods = ($d->{classes}{Pair}{methods} // {})->%*;
    ok(!exists $methods{left},  'left is NOT a user-method (it is a synthesized reader)');
    ok(!exists $methods{right}, 'right is NOT a user-method (it is a synthesized reader)');
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
