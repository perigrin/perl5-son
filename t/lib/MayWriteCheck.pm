# ABOUTME: Loaded before -MO=SoN, it reports each slot a loop's sealing finds rebound with no
# ABOUTME: header Phi (the may-write scan missed it): `MISS key where` on STDERR.
package MayWriteCheck;
use v5.42.0;
use SoN::FromOptree;

# Braun's header has a Phi for each slot the scan says the body may rebind
# (wire v2 plan, 5.2 and Q6). A slot the scan missed is learned at sealing
# (_braun_seal: the hint's `extra`) and the sub walked again: each one learned
# is a MISS of the scan.
my $orig = \&SoN::FromOptree::_braun_seal;
no warnings 'redefine';
*SoN::FromOptree::_braun_seal = sub {
    my $hint = $_[3];
    my %had = %{ $hint->{extra} };
    my $r = $orig->(@_);
    printf STDERR "MISS %s\n", $_ for grep { !$had{$_} } sort keys %{ $hint->{extra} };
    return $r;
};

1;
