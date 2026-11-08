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
        # SCALAR, NOT Str -- the formal type system's two-factor subtyping
        # test, both factors applied. Factor 2 (substitutability) passes:
        # every string operation works on a boolean uncoerced. Factor 1
        # (containment) FAILS, and a negative here must exhaust every
        # admissible reference type. Direct Str interpretation of `false` is
        # "", and measured on 5.42.0:
        #
        #     S=Num        detour "0"  FAILS
        #     S=Int        detour "0"  FAILS
        #     S=ScalarRef  identity on every Str -- the vacuous test the
        #                  well-formedness note excludes
        #     S=Boolean    circular: the stratification is
        #                  Scalar/List -> Str -> Num -> Int, with "Ref,
        #                  Boolean, etc. use Scalar"
        #
        # `true` PASSES via S=Num (1 -> "1" -> "1"); the counterexample is
        # `false` alone, which is why testing one value or one factor reached
        # the wrong answer. perl-type-system-formal.md states the conclusion
        # directly -- "Scalar contains values that belong neither to Str nor
        # to Num - including Boolean" -- and its hierarchy makes Boolean a
        # child of Scalar, sibling to Str.
        Boolean   => [qw(Scalar)],
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
        # MAYBE[T] IS T|Undef. Rules, not %PARENTS edges: edges would make
        # join(T, Undef) Maybe[T] everywhere, which is stage 2 (chalk's
        # t1-shape-from-t2.md); here only a stamp that says Maybe is one.
        if (defined( my $t = _maybe_of($type) )) {
            die "Unknown stamp type: $type"
                unless exists $PARENTS{$t} && $t !~ /\A(?:None|Unknown)\z/
                    && !_below('Undef', $t);
            return;
        }
        die "Unknown stamp type: $type" unless exists $PARENTS{$type};
    }

    sub _maybe_of ($t) { return $t =~ /\AMaybe\[(.+)\]\z/ ? $1 : undef }

    # _below($child, $parent) -> $child <: $parent, by name, Maybe included.
    sub _below ($c, $p) {
        return true if $c eq $p || $c eq 'None';
        if (defined( my $pt = _maybe_of($p) )) {
            return true if $c eq 'Undef';
            return _below(_maybe_of($c) // $c, $pt);
        }
        if (defined( my $ct = _maybe_of($c) )) {
            return _below('Undef', $p) && _below($ct, $p) ? true : false;
        }
        return exists _ancestors($c)->{$p} ? true : false;
    }

    # _maybe_type($t) -> T|Undef by name: a type already holding undef is itself.
    sub _maybe_type ($t) {
        return 'Unknown' if $t eq 'Unknown';
        return 'Undef'   if $t eq 'None' || $t eq 'Undef';
        return $t if defined _maybe_of($t) || _below('Undef', $t);
        return "Maybe[$t]";
    }

    method is_subtype_of ($other) {
        my $other_type = $other->type;
        return false if $type eq $other_type;

        # None is below everything; nothing but None is below None.
        return true  if $type eq 'None';
        return false if $other_type eq 'None';

        return _below($type, $other_type)
            if defined _maybe_of($type) || defined _maybe_of($other_type);

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

        # Maybe[A] meets B in two parts: A with B, and Undef with B.
        for my $pair ([ $left, $right ], [ $right, $left ]) {
            my ($m, $other) = @$pair;
            my $t = _maybe_of($m->type) // next;
            my $d = meet(SoN::IR::Stamp->new(type => $t), $other)->type;
            my $u = meet(SoN::IR::Stamp->new(type => 'Undef'), $other)->type;
            return SoN::IR::Stamp->new(type =>
                $d eq 'None' ? $u : $u eq 'None' ? $d : _maybe_type($d));
        }

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

        # A Maybe absorbs Undef and joins its T with the other side's.
        my ($lm, $rm) = (_maybe_of($lt), _maybe_of($rt));
        if (defined $lm || defined $rm) {
            my ($l, $r) = ($lm // $lt, $rm // $rt);
            my $t = $r eq 'Undef' ? $l : $l eq 'Undef' ? $r
                  : SoN::IR::Stamp::join(SoN::IR::Stamp->new(type => $l), SoN::IR::Stamp->new(type => $r))->type;
            return SoN::IR::Stamp->new(type => _maybe_type($t));
        }

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
