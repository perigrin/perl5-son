# ABOUTME: Tests for the SoN::ClassAux XS component (class HvAUX accessors).
# ABOUTME: Reaches the field-init CV, ADJUST CVs, and superclass that B:: hides.

use v5.42.0;
use feature 'class';
use Test2::V0;
use B;
no warnings 'experimental::class';

use SoN::ClassAux;

# A feature-class class stores its field initializers and ADJUST blocks as
# separate CVs on the HvAUX struct (not in the built-in `new` XSUB). ClassAux
# exposes them so B::SoN can translate field defaults and ADJUST bodies.

class Counter {
    field $n :param = 42;
    field $d;
    ADJUST { $d = $n * 2 }
    method val { $d }
}

class Child :isa(Counter) { }

package PlainPkg { sub regular { 1 } }

subtest 'is_class distinguishes a class from a plain package' => sub {
    ok(SoN::ClassAux::is_class(\%Counter::),  'Counter is a class');
    ok(SoN::ClassAux::is_class(\%Child::),    'Child is a class');
    ok(!SoN::ClassAux::is_class(\%PlainPkg::), 'PlainPkg is not a class');
};

subtest 'initfields_cv returns a walkable field-init CV' => sub {
    my $cv_ref = SoN::ClassAux::initfields_cv(\%Counter::);
    ok(defined $cv_ref, 'got an initfields CV');
    my $cv    = B::svref_2object($cv_ref);
    my $start = $cv->START;
    ok($$start, 'the field-init CV has a real (walkable) optree');
    my @ops;
    my $o = $start;
    while ($$o) { push @ops, $o->name; $o = $o->next }
    ok((grep { $_ eq 'const' } @ops),
        'the field-init optree contains the default value (const)');
    ok((grep { $_ eq 'initfield' } @ops),
        'the field-init optree contains initfield ops');
};

subtest 'adjust_cvs returns the ADJUST blocks as CVs' => sub {
    my @cvs = SoN::ClassAux::adjust_cvs(\%Counter::);
    is(scalar @cvs, 1, 'Counter has one ADJUST block');
    my $cv    = B::svref_2object($cvs[0]);
    my $start = $cv->START;
    ok($$start, 'the ADJUST CV has a walkable optree');
    my @ops;
    my $o = $start;
    while ($$o) { push @ops, $o->name; $o = $o->next }
    ok((grep { $_ eq 'multiply' } @ops),
        'the ADJUST optree contains the $n * 2 multiply');

    # xhv_class_adjust_blocks is the FLATTENED chain (own + inherited, in MRO
    # order), matching Perl's construction-time order. Child inherits Counter's.
    my @inherited = SoN::ClassAux::adjust_cvs(\%Child::);
    is(scalar @inherited, 1, 'Child inherits Counter\'s one ADJUST block');
};

subtest 'superclass_name returns the :isa parent' => sub {
    is(SoN::ClassAux::superclass_name(\%Child::), 'Counter',
        'Child :isa(Counter)');
    is(SoN::ClassAux::superclass_name(\%Counter::), undef,
        'Counter has no parent');
};

done_testing();
