# ABOUTME: Top-level module for the SoN (Sea of Nodes) IR distribution.
# ABOUTME: Provides version and loads core components.

use v5.42.0;
use feature 'class';

package SoN;

our $VERSION = '0.01';

1;

__END__

=head1 NAME

SoN - Sea of Nodes Intermediate Representation for Perl 5

=head1 DESCRIPTION

SoN provides a Sea of Nodes intermediate representation suitable for
representing Perl computations, along with an optree-to-SoN translator
and tools for graph comparison and rendering.

=head1 AUTHOR

Chris Prather C<chris@prather.org>

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
