# ABOUTME: OpMap's pop_count must be consistent with perl's own op CLASS --
# ABOUTME: a LOOPEXOP pops nothing, a BINOP pops two, a childless OP pops none.
use v5.42.0;
use Test2::V0;

use SoN::FromOptree::OpMap;

# WHY THIS EXISTS. OpMap is 350 hand-written entries and a wrong pop_count is
# invisible until some program happens to reach that op. `goto` carried
# pop_count=1 for its entire life; it is a LOOPEXOP, a control transfer whose
# label rides on the op itself, so it takes NO stack operand. The generic op
# handler popped an operand that does not exist and underflowed the StackSim
# BEFORE goto's own (correct, long-present) GAP could name the construct --
# so the refusal never ran and the reader was pointed at a simulator bug.
#
# perl already knows each op's class, and the class CONSTRAINS the pop count:
#
#     LOOPEXOP   last/next/redo/goto -- transfers control, pops nothing
#     BINOP      exactly two children
#     OP         no children at all
#
# The table below is perl's classification (via Stevan Little's Allium
# instruction-set data, generated from perl itself). It covers only the three
# classes with an unambiguous rule -- UNOP is deliberately excluded, because a
# UNOP's child is sometimes consumed structurally by a handler rather than
# popped, and LISTOP uses the 'mark' discipline instead of a count.
my %OP_CLASS = (
    aassign => 'BINOP', add => 'BINOP', aelem => 'BINOP',
    aelemfast_lex => 'OP', bit_and => 'BINOP', bit_or => 'BINOP',
    bit_xor => 'BINOP', classname => 'OP', clonecv => 'OP',
    concat => 'BINOP', custom => 'OP', divide => 'BINOP',
    dump => 'LOOPEXOP', egrent => 'OP', ehostent => 'OP',
    emptyavhv => 'OP', enetent => 'OP', enter => 'OP', eprotoent => 'OP',
    epwent => 'OP', eq => 'BINOP', eservent => 'OP', fork => 'OP',
    ge => 'BINOP', gelem => 'BINOP', getlogin => 'OP', getppid => 'OP',
    ggrent => 'OP', ghostent => 'OP', gnetent => 'OP', goto => 'LOOPEXOP',
    gprotoent => 'OP', gpwent => 'OP', gservent => 'OP', gt => 'BINOP',
    helem => 'BINOP', i_add => 'BINOP', i_divide => 'BINOP',
    i_eq => 'BINOP', i_ge => 'BINOP', i_gt => 'BINOP', i_le => 'BINOP',
    i_lt => 'BINOP', i_modulo => 'BINOP', i_multiply => 'BINOP',
    i_ncmp => 'BINOP', i_ne => 'BINOP', i_subtract => 'BINOP',
    introcv => 'OP', isa => 'BINOP', iter => 'OP', last => 'LOOPEXOP',
    le => 'BINOP', leaveloop => 'BINOP', left_shift => 'BINOP',
    lslice => 'BINOP', lt => 'BINOP', modulo => 'BINOP',
    multiply => 'BINOP', nbit_and => 'BINOP', nbit_or => 'BINOP',
    nbit_xor => 'BINOP', ncmp => 'BINOP', ne => 'BINOP',
    next => 'LOOPEXOP', null => 'OP', padany => 'OP', padav => 'OP',
    padcv => 'OP', padhv => 'OP', padrange => 'OP', padsv => 'OP',
    pow => 'BINOP', pushmark => 'OP', redo => 'LOOPEXOP',
    refassign => 'BINOP', repeat => 'BINOP', right_shift => 'BINOP',
    runcv => 'OP', sassign => 'BINOP', sbit_and => 'BINOP',
    sbit_or => 'BINOP', sbit_xor => 'BINOP', scmp => 'BINOP',
    seq => 'BINOP', sge => 'BINOP', sgrent => 'OP', sgt => 'BINOP',
    sle => 'BINOP', slt => 'BINOP', sne => 'BINOP', spwent => 'OP',
    stub => 'OP', subtract => 'BINOP', time => 'OP', tms => 'OP',
    unstack => 'OP', wait => 'OP', wantarray => 'OP', xor => 'BINOP',
);

subtest 'pop_count agrees with the op class' => sub {
    my $m = SoN::FromOptree::OpMap->new;
    my @violations;

    for my $name (sort keys %OP_CLASS) {
        next unless $m->is_known($name);
        my $pop = $m->pop_count($name);
        next unless defined $pop;
        next if $pop eq 'mark';          # variadic, no fixed count
        my $class = $OP_CLASS{$name};

        if ($class eq 'LOOPEXOP') {
            push @violations, "$name is a LOOPEXOP (control transfer) but"
                            . " pops $pop" if $pop != 0;
        }
        elsif ($class eq 'OP') {
            push @violations, "$name is a childless OP but pops $pop"
                if $pop != 0;
        }
        elsif ($class eq 'BINOP') {
            # A branching BINOP (leaveloop) is walked structurally, not popped.
            next if $m->is_branch($name) || $m->is_loop($name);
            push @violations, "$name is a BINOP (two children) but pops $pop"
                if $pop != 2;
        }
    }

    diag("  $_") for @violations;
    is(\@violations, [], 'no op contradicts its class');
};

subtest 'the rule that would have caught the goto bug' => sub {
    my $m = SoN::FromOptree::OpMap->new;
    is($m->pop_count('goto'), 0,
        'goto pops nothing -- its label rides on the op, not the stack');
};

done_testing;
