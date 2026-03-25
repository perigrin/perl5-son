# ABOUTME: Mapping table from perl5 opcodes to SoN node types and stack effects.
# ABOUTME: Defines pop count, push count, node type, and flags for each opcode.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::FromOptree::OpMap 0.01 {
    # Each entry: [pop_count, node_type, push_count, flags]
    # pop_count: integer or 'mark' (pop to last mark)
    # node_type: SoN node operation name, or undef for skip/special
    # push_count: 0 or 1
    # flags: bitmask - 1=skip, 2=cfg(branch), 4=cfg(loop)

    use constant SKIP   => 1;
    use constant BRANCH => 2;
    use constant LOOP   => 4;

    my %MAP = (
        # Bookkeeping - skip these
        null      => [0, undef,     0, SKIP],
        stub      => [0, undef,     0, SKIP],
        enter     => [0, undef,     0, SKIP],
        leave     => [0, undef,     0, SKIP],
        nextstate => [0, undef,     0, SKIP],
        pushmark  => [0, undef,     0, SKIP],  # handled specially
        unstack   => [0, undef,     0, SKIP],
        scope     => [0, undef,     0, SKIP],
        lineseq   => [0, undef,     0, SKIP],
        dbstate   => [0, undef,     0, SKIP],

        # Constants
        const     => [0, 'Constant', 1, 0],

        # Pad (lexical) variable access
        padsv     => [0, 'PadAccess', 1, 0],
        padsv_store => [1, 'Assign',  1, 0],  # optimized assign to pad
        padav     => [0, 'PadAccess', 1, 0],
        padhv     => [0, 'PadAccess', 1, 0],

        # Global variable access
        gvsv      => [0, 'StashAccess', 1, 0],
        rv2sv     => [1, 'StashAccess', 1, 0],

        # Arithmetic
        add       => [2, 'Add',      1, 0],
        subtract  => [2, 'Subtract', 1, 0],
        multiply  => [2, 'Multiply', 1, 0],
        divide    => [2, 'Divide',   1, 0],
        negate    => [1, 'Negate',   1, 0],
        i_add     => [2, 'Add',      1, 0],
        i_subtract => [2, 'Subtract', 1, 0],
        i_multiply => [2, 'Multiply', 1, 0],
        i_divide  => [2, 'Divide',   1, 0],
        i_negate  => [1, 'Negate',   1, 0],
        modulo    => [2, 'Modulo',   1, 0],
        pow       => [2, 'Power',    1, 0],

        # String
        concat    => [2, 'Concat',   1, 0],
        length    => [1, 'Length',   1, 0],
        stringify => [1, 'Stringify', 1, 0],
        multiconcat => ['mark', 'Concat', 1, 0],

        # Numeric comparison
        eq        => [2, 'NumEq',    1, 0],
        lt        => [2, 'NumLt',    1, 0],
        gt        => [2, 'NumGt',    1, 0],
        le        => [2, 'NumLe',    1, 0],
        ge        => [2, 'NumGe',    1, 0],
        ne        => [2, 'NumNe',    1, 0],
        ncmp      => [2, 'NumCmp',   1, 0],
        i_eq      => [2, 'NumEq',    1, 0],
        i_lt      => [2, 'NumLt',    1, 0],
        i_gt      => [2, 'NumGt',    1, 0],
        i_le      => [2, 'NumLe',    1, 0],
        i_ge      => [2, 'NumGe',    1, 0],
        i_ne      => [2, 'NumNe',    1, 0],
        i_ncmp    => [2, 'NumCmp',   1, 0],

        # String comparison
        seq       => [2, 'StrEq',    1, 0],
        slt       => [2, 'StrLt',    1, 0],
        sgt       => [2, 'StrGt',    1, 0],
        sle       => [2, 'StrLe',    1, 0],
        sge       => [2, 'StrGe',    1, 0],
        sne       => [2, 'StrNe',    1, 0],
        scmp      => [2, 'StrCmp',   1, 0],

        # Logical / control flow
        and       => [1, undef,      1, BRANCH],
        or        => [1, undef,      1, BRANCH],
        not       => [1, 'Not',      1, 0],
        cond_expr => [1, undef,      1, BRANCH],
        defined   => [1, 'Defined',  1, 0],

        # Assignment
        sassign   => [2, 'Assign',   1, 0],

        # Subroutine calls
        entersub  => ['mark', 'Call', 1, 0],
        method_named => [1, undef,   1, 0],  # handled specially with entersub

        # Return
        return    => ['mark', undef,  0, 0],   # handled specially
        leavesub  => [1, undef,       1, 0],   # handled specially
        leavesublv => [1, undef,      1, 0],

        # Loops
        enterloop => [0, undef,      0, LOOP],
        leaveloop => [2, undef,      0, 0],
        iter      => [0, undef,      1, BRANCH],
        enteriter => [0, undef,      0, LOOP],

        # Try/catch
        entertry  => [0, undef,      0, BRANCH],
        leavetry  => [1, undef,      1, 0],
        catch     => [0, undef,      0, BRANCH],

        # Array/hash operations (basic set)
        aelem     => [2, 'Subscript', 1, 0],
        helem     => [2, 'Subscript', 1, 0],
        rv2av     => [1, undef,       1, SKIP],
        rv2hv     => [1, undef,       1, SKIP],
        aslice    => ['mark', 'Slice', 1, 0],
        hslice    => ['mark', 'Slice', 1, 0],
        push      => ['mark', 'Call',  1, 0],
        pop       => [1, 'Call',       1, 0],
        shift     => [1, 'Call',       1, 0],
        unshift   => ['mark', 'Call',  1, 0],
        keys      => [1, 'Call',       1, 0],
        values    => [1, 'Call',       1, 0],
        each      => [1, 'Call',       1, 0],
        exists    => [1, 'Defined',    1, 0],
        delete    => [1, 'Call',       1, 0],
        splice    => ['mark', 'Call',  1, 0],

        # Misc
        undef     => [0, 'Constant',  1, 0],  # undef literal
        wantarray => [0, 'Constant',  1, 0],
        caller    => [0, 'Call',       1, 0],
        die       => ['mark', 'Call',  1, 0],
        warn      => ['mark', 'Call',  1, 0],
        print     => ['mark', 'Call',  1, 0],
        say       => ['mark', 'Call',  1, 0],
        chr       => [1, 'Call',       1, 0],
        ord       => [1, 'Call',       1, 0],
        hex       => [1, 'Call',       1, 0],
        oct       => [1, 'Call',       1, 0],
        abs       => [1, 'Call',       1, 0],
        sqrt      => [1, 'Call',       1, 0],
        int       => [1, 'Call',       1, 0],
        ref       => [1, 'Call',       1, 0],
    );

    method lookup ($opname) {
        return $MAP{$opname};
    }

    method is_skip ($opname) {
        my $entry = $MAP{$opname} // return false;
        return ($entry->[3] & SKIP) ? true : false;
    }

    method is_branch ($opname) {
        my $entry = $MAP{$opname} // return false;
        return ($entry->[3] & BRANCH) ? true : false;
    }

    method is_loop ($opname) {
        my $entry = $MAP{$opname} // return false;
        return ($entry->[3] & LOOP) ? true : false;
    }

    method pop_count ($opname) {
        my $entry = $MAP{$opname} // return undef;
        return $entry->[0];
    }

    method node_type ($opname) {
        my $entry = $MAP{$opname} // return undef;
        return $entry->[1];
    }

    method push_count ($opname) {
        my $entry = $MAP{$opname} // return undef;
        return $entry->[2];
    }

    method is_known ($opname) {
        return exists $MAP{$opname};
    }
}

1;
