# ABOUTME: Type lattice metadata for SoN node edges.
# ABOUTME: Implements the formal Perl type lattice (Int < Num < Str < Scalar).

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Stamp 0.01 {
    # The lattice as a DAG. Each type maps to its direct parents.
    # Based on https://pvm.tools/papers/perl-types-formal.html
    my %PARENTS = (
        Scalar    => [qw(List)],
        Void      => [qw(List)],
        Undef     => [qw(Scalar)],
        Str       => [qw(Scalar)],
        Num       => [qw(Str)],
        Int       => [qw(Num)],
        Boolean   => [qw(Str)],
        VString   => [qw(Str)],
        DualVar   => [qw(Scalar)],
        Ref       => [qw(Scalar)],
        Object    => [qw(Ref)],
        Regex     => [qw(Object)],
        ScalarRef => [qw(Ref)],
        LValueRef => [qw(ScalarRef)],
        ArrayRef  => [qw(Ref)],
        HashRef   => [qw(Ref)],
        CodeRef   => [qw(Ref)],
        GlobRef   => [qw(Ref)],
        List      => [qw(Unknown)],
        Array     => [qw(List)],
        Hash      => [qw(List)],
        Code      => [qw(Unknown)],
        Glob      => [qw(Unknown)],
        IO        => [qw(Unknown)],
        Format    => [qw(Unknown)],
        None      => [],
        Unknown   => [],
    );

    # Precompute the full set of ancestors for each type
    my %ANCESTORS;
    sub _ancestors ($type) {
        return $ANCESTORS{$type} if exists $ANCESTORS{$type};
        my %seen;
        my @queue = ($type);
        while (my $t = shift @queue) {
            next if $seen{$t}++;
            for my $parent (($PARENTS{$t} // [])->@*) {
                push @queue, $parent;
            }
        }
        $ANCESTORS{$type} = \%seen;
        return \%seen;
    }

    # Precompute depth (distance from Unknown) for LUB calculation
    my %DEPTH;
    sub _depth ($type) {
        return $DEPTH{$type} if exists $DEPTH{$type};
        my $parents = $PARENTS{$type} // [];
        if (!$parents->@*) {
            return $DEPTH{$type} = 0;  # Unknown is depth 0
        }
        my $max = 0;
        for my $p ($parents->@*) {
            my $d = _depth($p);
            $max = $d if $d > $max;
        }
        return $DEPTH{$type} = $max + 1;
    }

    field $type :param :reader;

    ADJUST {
        die "Unknown stamp type: $type" unless exists $PARENTS{$type};
    }

    method is_subtype_of ($other) {
        my $other_type = $other->type;
        return false if $type eq $other_type;

        # None is below everything; nothing but None is below None.
        return true  if $type eq 'None';
        return false if $other_type eq 'None';

        my $ancestors = _ancestors($type);
        return exists $ancestors->{$other_type} ? true : false;
    }

    # Greatest lower bound: the most specific type that is a subtype of both
    # Parameters are $left/$right, not $a/$b: perl's sort localizes the $a and
    # $b globals, so the comparator below shadowed them under the old names.
    sub meet ($left, $right) {
        my $lt = $left->type;
        my $rt = $right->type;
        return $left if $lt eq $rt;

        return $left  if $lt eq 'None';
        return $right if $rt eq 'None';

        # If one is subtype of the other, that's the meet
        return $left  if $left->is_subtype_of($right);
        return $right if $right->is_subtype_of($left);

        # Look for a type below both, deepest first, so the result is the
        # GREATEST such lower bound rather than merely a lower bound.
        for my $candidate (sort { _depth($b) <=> _depth($a) || $a cmp $b }
                           keys %PARENTS) {
            my $c_anc = _ancestors($candidate);
            if (exists $c_anc->{$lt} && exists $c_anc->{$rt}) {
                return SoN::IR::Stamp->new(type => $candidate);
            }
        }

        # Nothing inhabits both: bottom is the correct answer, not an error.
        return SoN::IR::Stamp->new(type => 'None');
    }

    # Least upper bound: the most specific type that both are subtypes of
    sub join ($left, $right) {
        my $lt = $left->type;
        my $rt = $right->type;
        return $left if $lt eq $rt;

        # None is the identity. That is what lets a recursive function type
        # from its base case: the recursive arm contributes None on the first
        # pass, so join(Int, None) is Int rather than a widening to the top.
        return $right if $lt eq 'None';
        return $left  if $rt eq 'None';

        # If one is subtype of the other, the supertype is the join
        return $right if $left->is_subtype_of($right);
        return $left  if $right->is_subtype_of($left);

        # Nearest common ancestor: deepest type in both ancestor sets. Sorted
        # so the result does not depend on hash order.
        my $left_anc  = _ancestors($lt);
        my $right_anc = _ancestors($rt);

        my $best_type  = 'Unknown';
        my $best_depth = -1;

        for my $t (sort keys %$left_anc) {
            next unless exists $right_anc->{$t};
            my $d = _depth($t);
            if ($d > $best_depth) {
                $best_depth = $d;
                $best_type  = $t;
            }
        }

        return SoN::IR::Stamp->new(type => $best_type);
    }
}

1;
