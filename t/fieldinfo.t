# ABOUTME: Tests for SoN::FieldInfo XS component.
# ABOUTME: Verifies field metadata access for feature class fields.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use Test2::V0;
use B;

use SoN::FieldInfo;

# A test class with fields
class TestFieldInfo {
    field $x :param :reader;
    field $y :param :reader;
    field $label :param = 'default';

    method sum () { $x + $y }
}

# Helper: find a padname by variable name in a CV
sub find_padname ($cv, $name) {
    my @padnames = $cv->PADLIST->ARRAYelt(0)->ARRAY;
    for my $pn (@padnames) {
        next unless ref $pn eq 'B::PADNAME';
        my $pv = eval { $pn->PV };
        next unless defined $pv && $pv eq $name;
        return $pn;
    }
    return undef;
}

subtest 'is_field returns true for class field padnames' => sub {
    my $cv = B::svref_2object(\&TestFieldInfo::sum);
    my $pn = find_padname($cv, '$x');
    ok(defined $pn, 'found $x padname in sum()');
    ok(SoN::FieldInfo::is_field($pn), '$x is a field') if defined $pn;
};

subtest 'is_field returns false for regular lexicals' => sub {
    my $sub = eval 'sub { my $regular = 42; $regular }';
    my $cv = B::svref_2object($sub);
    my $pn = find_padname($cv, '$regular');
    ok(defined $pn, 'found $regular padname');
    ok(!SoN::FieldInfo::is_field($pn), '$regular is not a field') if defined $pn;
};

subtest 'field_info returns correct metadata' => sub {
    my $cv = B::svref_2object(\&TestFieldInfo::sum);
    my $pn = find_padname($cv, '$x');
    ok(defined $pn, 'found $x padname');
    if (defined $pn && SoN::FieldInfo::is_field($pn)) {
        my @info = SoN::FieldInfo::field_info($pn);
        ok(scalar @info >= 3, 'field_info returns at least 3 values');
        like($info[0], qr/^\d+$/, 'field index is a number');
        is($info[1], 'TestFieldInfo', 'field stash is TestFieldInfo');
    }
};

subtest 'field_info returns paramname' => sub {
    my $cv = B::svref_2object(\&TestFieldInfo::sum);
    my $pn = find_padname($cv, '$x');
    if (defined $pn && SoN::FieldInfo::is_field($pn)) {
        my @info = SoN::FieldInfo::field_info($pn);
        # $x has :param, so paramname should be 'x'
        is($info[2], 'x', 'paramname is x for :param field');
    }
};

subtest 'handles non-field padnames safely' => sub {
    my $sub = eval 'sub { my $z = 1; $z }';
    my $cv = B::svref_2object($sub);
    my $pn = find_padname($cv, '$z');
    ok(defined $pn, 'found $z padname');
    if (defined $pn) {
        my @info = SoN::FieldInfo::field_info($pn);
        is(scalar @info, 0, 'field_info returns empty for non-field');
    }
};

done_testing;
