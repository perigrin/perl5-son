# ABOUTME: Perl-side loader for the FieldInfo XS component.
# ABOUTME: Exposes PadnameFIELDINFO accessors for feature class field metadata.

use v5.42.0;

package SoN::FieldInfo;

our $VERSION = '0.01';

# XS functions live in the SoN shared object, load it once
require SoN;

1;
