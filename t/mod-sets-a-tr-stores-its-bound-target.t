# ABOUTME: ModSets: `$x =~ tr/a/z/` stores $x -- the target is the trans's elder sibling under
# ABOUTME: the `=~`, not a kid as s///'s is; a counting tr/// and tr///r store nothing.
use v5.42.0;
use Test2::V0;
use B;
use B::SoN;
use B::SoN::EffectTable;
use SoN::FromOptree::ModSets;

our $g;
package O {
    sub arg   { $_[0] =~ tr/a/z/ }
    sub argy  { $_[0] =~ y/b/z/ }
    sub pkg   { $main::g =~ tr/a/z/ }
    sub count { $_[0] =~ tr/a// }
    sub copy  { $_[0] =~ tr/a/z/r }
    sub subst { $_[0] =~ s/a/z/ }
}

sub locs ($code) { [ sort map { $_->{loc} } SoN::FromOptree::ModSets::summary( B::svref_2object($code) )->@* ] }

# THE DEFECT (audit 3, risk 2). `$_[0] =~ tr/a/z/` compiles to
# null(STACKED)[ex-aelem, trans]: the trans op has no kids, and the scans took
# a stacked store's target from its first kid, as s///'s is. So a sub storing
# its argument by tr/// stored nothing: its `my ($p) = @_` copy stayed a
# record (ya37: `zbzb` for perl's `abzb`), and `print $g, $g =~ tr/a/z/` read
# $g before the store (yp178: `ab1` for `zb1`).
is locs( \&O::arg ),   ['P'],         'tr/// through $_[0] stores the argument';
is locs( \&O::argy ),  ['P'],         'y/// is tr///';
is locs( \&O::pkg ),   ['N:$main::g'], 'tr/// on a package scalar stores it';
is locs( \&O::count ), [],            'a counting tr/// stores nothing';
is locs( \&O::copy ),  [],            'tr///r stores nothing';
is locs( \&O::subst ), ['P'],         's/// still stores its target';

# ONE FACT, IN THE TABLE: which operand a binding builtin stores.
my $trans = sub ($code) {
    my ($t) = grep { $_->name eq 'trans' } map { _ops($_) } B::svref_2object($code)->ROOT;
    return $t;
};
my $t = $trans->( \&O::arg );
ok $t, 'found the trans op';
my $bt = B::SoN::EffectTable::bound_target($t);
is $bt->name eq q{null} ? B::ppname( $bt->targ ) =~ s{\App_}{}r : $bt->name, "aelem", q{its bound target is the $_[0] before it (an aelem, or an ex-aelem when peeped)};
ok !defined B::SoN::EffectTable::bound_target( $trans->( \&O::count ) ), 'a counting tr has none';

sub _ops ($o) {
    my @out = ($o);
    if ( $o->flags & B::OPf_KIDS ) { for ( my $k = $o->first; $$k; $k = $k->sibling ) { push @out, _ops($k) } }
    return @out;
}

done_testing;
