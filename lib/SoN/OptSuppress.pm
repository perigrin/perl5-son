# ABOUTME: Perl-side loader for the peephole-optimizer suppression XS component.
# ABOUTME: suppress_peep()/restore_peep() swap PL_rpeepp so optrees stay unfused.

use v5.42.0;

package SoN::OptSuppress;

our $VERSION = '0.01';

# XS functions (suppress_peep / restore_peep) live in the SoN shared object.
require SoN;

1;
