# ABOUTME: Type lattice metadata for SoN node edges.
# ABOUTME: Implements the formal Perl type lattice (Int < Num < Str < Scalar).

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Stamp 0.01 {
    # The lattice as a DAG. Each type maps to its direct parents.
    # Based on https://pvm.tools/papers/perl-types-formal.html
    my %PARENTS = (
        None      => [qw(Int Boolean Undef ScalarRef ArrayRef HashRef CodeRef Object DualVar)],
        Int       => [qw(Num)],
        Num       => [qw(Str)],
        Str       => [qw(Scalar)],
        Boolean   => [qw(Scalar)],
        Undef     => [qw(Scalar)],
        DualVar   => [qw(Scalar)],
        Ref       => [qw(Scalar)],
        ScalarRef => [qw(Ref)],
        ArrayRef  => [qw(Ref)],
        HashRef   => [qw(Ref)],
        CodeRef   => [qw(Ref)],
        Object    => [qw(Ref)],
        Scalar    => [qw(Unknown)],
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
        return false if $type eq $other->type;
        my $ancestors = _ancestors($type);
        return exists $ancestors->{$other->type} ? true : false;
    }

    # Greatest lower bound: the most specific type that is a subtype of both
    sub meet ($a, $b) {
        my $at = $a->type;
        my $bt = $b->type;
        return $a if $at eq $bt;

        # If one is subtype of the other, that's the meet
        return $a if $a->is_subtype_of($b);
        return $b if $b->is_subtype_of($a);

        # Find the deepest type that is an ancestor of both... but from below.
        # Check if any leaf type is a subtype of both.
        my $a_anc = _ancestors($at);
        my $b_anc = _ancestors($bt);

        # Find types that have both $at and $bt as ancestors
        for my $candidate (sort { _depth($b) <=> _depth($a) } keys %PARENTS) {
            my $c_anc = _ancestors($candidate);
            if (exists $c_anc->{$at} && exists $c_anc->{$bt}) {
                return SoN::IR::Stamp->new(type => $candidate);
            }
        }

        return SoN::IR::Stamp->new(type => 'None');
    }

    # Least upper bound: the most specific type that both are subtypes of
    sub join ($a, $b) {
        my $at = $a->type;
        my $bt = $b->type;
        return $a if $at eq $bt;

        # If one is subtype of the other, the supertype is the join
        return $b if $a->is_subtype_of($b);
        return $a if $b->is_subtype_of($a);

        # Find common ancestors, pick the deepest one
        my $a_anc = _ancestors($at);
        my $b_anc = _ancestors($bt);

        my $best_type  = 'Unknown';
        my $best_depth = 0;

        for my $t (keys %$a_anc) {
            if (exists $b_anc->{$t}) {
                my $d = _depth($t);
                if ($d > $best_depth) {
                    $best_depth = $d;
                    $best_type  = $t;
                }
            }
        }

        return SoN::IR::Stamp->new(type => $best_type);
    }
}

1;
