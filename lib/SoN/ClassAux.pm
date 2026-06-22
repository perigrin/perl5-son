# ABOUTME: Perl-side loader for the class-aux XS accessors.
# ABOUTME: Exposes is_class / initfields_cv / adjust_cvs / superclass_name from HvAUX.

use v5.42.0;

package SoN::ClassAux;

our $VERSION = '0.01';

# XS functions live in the SoN shared object.
require SoN;

1;
