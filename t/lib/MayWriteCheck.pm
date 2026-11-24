# ABOUTME: Loaded before -MO=SoN, it reports each slot a loop's sealing finds rebound with no
# ABOUTME: header Phi (the may-write scan missed it): `MISS key where` on STDERR.
package MayWriteCheck;
use v5.42.0;
use SoN::FromOptree;

# Braun's header has a Phi for each slot the scan says the body may rebind
# (wire v2 plan, 5.2 and Q6). A slot the scan missed is refused at sealing
# (_braun_seal: "its header's scan missed"): each one is a MISS of the scan.
my $orig = \&SoN::FromOptree::_braun_seal;
no warnings 'redefine';
*SoN::FromOptree::_braun_seal = sub {
    my @r = eval { $orig->(@_) };
    if ( my $e = $@ ) {
        printf STDERR "MISS %s\n", $1 if $e =~ /its header's scan missed \((.*?)\)/;
        die $e;
    }
    return wantarray ? @r : $r[0];
};

1;
