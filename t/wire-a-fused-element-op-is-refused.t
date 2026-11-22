# ABOUTME: A peephole-fused `aelemfast` of a package array (code perl compiled before B::SoN turned
# ABOUTME: the optimizer off: DynaLoader) is refused by name, not walked as an element of nothing.
use v5.42.0;
use Test2::V0;
use JSON::PP;

# TRACED (the DynaLoader hold, audit 2026-11-22 section 6): perl loads
# DynaLoader at startup, so its subs are compiled with the peephole optimizer
# on. `$_[0]` is `aelemfast[*_]`, which the op map made a Subscript with no
# inputs; and the list assign after it lost its list -- the `record` the
# verifier held was the wreck of that, not a store. Refused instead.
my $w = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN -e 'use DynaLoader; print "x\\n"' 2>/dev/null);
my $wire = JSON::PP->new->decode($w);
my $g = $wire->{methods};
ok !exists $g->{'DynaLoader::bootstrap_inherit'}, 'bootstrap_inherit is not on the wire';
ok !exists $g->{'DynaLoader::bootstrap'}, 'nor bootstrap';
like $wire->{refused}{$_}, qr/\AGAP: .*aelemfast/, "$_ refused by name" for qw(DynaLoader::bootstrap DynaLoader::bootstrap_inherit);
is [ grep { $_->{op} eq 'Subscript' && !( $_->{inputs} // [] )->@* } map { $_->{nodes}->@* } values %$g ], [], 'no element of nothing anywhere';
done_testing;
