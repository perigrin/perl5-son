# ABOUTME: Translates perl5 compiled optrees into SoN IR graphs.
# ABOUTME: Uses stack simulation to reconstruct data flow from the op_next chain.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

use B;

class SoN::FromOptree 0.01 {
    use SoN::IR::NodeFactory;
    use SoN::IR::Graph;
    use SoN::IR::Stamp;
    use SoN::FromOptree::OpMap;
    use SoN::FromOptree::StackSim;

    # Translate a code reference to a SoN graph
    sub translate ($class_or_self, $coderef) {
        my $cv = B::svref_2object($coderef);
        die "Not a CODE ref" unless $cv->isa('B::CV');

        my $factory = SoN::IR::NodeFactory->new();
        my $opmap   = SoN::FromOptree::OpMap->new();
        my $start   = $factory->make_cfg('Start');
        my $sim     = SoN::FromOptree::StackSim->new(control => $start);

        my %visited;
        my $op = $cv->START;

        while ($$op) {
            last if $visited{$$op}++;

            my $name = $op->name;

            # Handle pushmark specially - just record the mark
            if ($name eq 'pushmark') {
                $sim->push_mark;
                $op = $op->next;
                next;
            }

            # Skip bookkeeping ops
            if ($opmap->is_skip($name)) {
                $op = $op->next;
                next;
            }

            # Branch and loop ops handled by subclasses/extensions
            if ($opmap->is_branch($name) || $opmap->is_loop($name)) {
                # For now, stop at branches (linear translation only)
                $op = $op->next;
                next;
            }

            # Handle return specially
            if ($name eq 'return') {
                my $args = $sim->pop_to_mark;
                my $retval = $args->@* ? $args->[-1] : $factory->make('Constant',
                    value => undef, stamp => SoN::IR::Stamp->new(type => 'Undef'));
                my $ret = $factory->make_cfg('Return',
                    inputs => [$sim->control, $retval]);
                my $graph = SoN::IR::Graph->new(
                    start   => $start,
                    returns => [$ret],
                    source  => $coderef,
                );
                return $graph;
            }

            # Handle leavesub - implicit return of top of stack
            if ($name eq 'leavesub' || $name eq 'leavesublv') {
                my $retval;
                if ($sim->stack_depth > 0) {
                    $retval = $sim->pop_node;
                } else {
                    $retval = $factory->make('Constant',
                        value => undef, stamp => SoN::IR::Stamp->new(type => 'Undef'));
                }
                my $ret = $factory->make_cfg('Return',
                    inputs => [$sim->control, $retval]);
                my $graph = SoN::IR::Graph->new(
                    start   => $start,
                    returns => [$ret],
                    source  => $coderef,
                );
                return $graph;
            }

            # Handle const specially - extract value from the op
            if ($name eq 'const') {
                my $sv = $op->sv;
                # For B::SPECIAL (shared constants), use the SV from padlist
                if (!$$sv || $sv->isa('B::SPECIAL')) {
                    my $targ = $op->targ;
                    my $padl = $cv->PADLIST;
                    if ($targ && $$padl) {
                        $sv = $padl->ARRAYelt(1)->ARRAYelt($targ);
                    }
                }
                my ($value, $stamp) = _extract_const($sv);
                my $node = $factory->make('Constant',
                    value => $value, stamp => $stamp);
                $sim->push_node($node);
                $op = $op->next;
                next;
            }

            # Handle padsv - lexical variable access
            if ($name eq 'padsv') {
                my $targ = $op->targ;
                my $varname = _padname($cv, $targ);
                # Check if already defined in scope (read) vs first use
                my $existing = $sim->lookup($targ);
                if ($existing) {
                    $sim->push_node($existing);
                } else {
                    my $node = $factory->make('PadAccess',
                        targ => $targ, varname => $varname);
                    $sim->define($targ, $node);
                    $sim->push_node($node);
                }
                $op = $op->next;
                next;
            }

            # Handle sassign - scalar assignment
            if ($name eq 'sassign') {
                my $value = $sim->pop_node;
                my $target = $sim->pop_node;
                # If target is a PadAccess, update the scope binding
                if ($target->isa('SoN::IR::Node::PadAccess')) {
                    $sim->define($target->targ, $value);
                }
                $sim->push_node($value);
                $op = $op->next;
                next;
            }

            # Handle padsv_store - optimized pad assignment
            if ($name eq 'padsv_store') {
                my $value = $sim->pop_node;
                my $targ = $op->targ;
                $sim->define($targ, $value);
                $sim->push_node($value);
                $op = $op->next;
                next;
            }

            # Generic op handling via OpMap
            if ($opmap->is_known($name)) {
                my $pop_count = $opmap->pop_count($name);
                my $node_type = $opmap->node_type($name);
                my $push_count = $opmap->push_count($name);

                my @inputs;
                if (defined $pop_count && $pop_count eq 'mark') {
                    my $args = $sim->pop_to_mark;
                    @inputs = $args->@*;
                } elsif (defined $pop_count && $pop_count > 0) {
                    for (1 .. $pop_count) {
                        unshift @inputs, $sim->pop_node;
                    }
                }

                if (defined $node_type) {
                    my $node = $factory->make($node_type, inputs => \@inputs);
                    if ($push_count) {
                        $sim->push_node($node);
                    }
                }

                $op = $op->next;
                next;
            }

            # Unknown op - skip with warning
            warn "SoN::FromOptree: unknown op '$name', skipping\n";
            $op = $op->next;
        }

        # If we fell through without a return/leavesub, build graph from stack
        my $retval;
        if ($sim->stack_depth > 0) {
            $retval = $sim->pop_node;
        } else {
            $retval = $factory->make('Constant',
                value => undef, stamp => SoN::IR::Stamp->new(type => 'Undef'));
        }
        my $ret = $factory->make_cfg('Return',
            inputs => [$sim->control, $retval]);
        return SoN::IR::Graph->new(
            start   => $start,
            returns => [$ret],
            source  => $coderef,
        );
    }

    # Extract value and stamp from a B::SV
    sub _extract_const ($sv) {
        return (undef, SoN::IR::Stamp->new(type => 'Undef'))
            unless defined $sv && $$sv;

        if ($sv->isa('B::IV')) {
            return ($sv->int_value, SoN::IR::Stamp->new(type => 'Int'));
        }
        elsif ($sv->isa('B::NV')) {
            return ($sv->NV, SoN::IR::Stamp->new(type => 'Num'));
        }
        elsif ($sv->isa('B::PV')) {
            return ($sv->PV, SoN::IR::Stamp->new(type => 'Str'));
        }
        elsif ($sv->isa('B::PVIV')) {
            # Could be either - check flags
            if ($sv->FLAGS & B::SVf_IOK()) {
                return ($sv->int_value, SoN::IR::Stamp->new(type => 'Int'));
            }
            return ($sv->PV, SoN::IR::Stamp->new(type => 'Str'));
        }
        elsif ($sv->isa('B::PVNV')) {
            if ($sv->FLAGS & B::SVf_NOK()) {
                return ($sv->NV, SoN::IR::Stamp->new(type => 'Num'));
            }
            if ($sv->FLAGS & B::SVf_IOK()) {
                return ($sv->int_value, SoN::IR::Stamp->new(type => 'Int'));
            }
            return ($sv->PV, SoN::IR::Stamp->new(type => 'Str'));
        }
        else {
            return (undef, SoN::IR::Stamp->new(type => 'Unknown'));
        }
    }

    # Get the variable name for a pad index
    sub _padname ($cv, $targ) {
        my $padlist = $cv->PADLIST;
        return '$?' unless $$padlist;
        my $padnames = $padlist->ARRAYelt(0);
        my $pn = $padnames->ARRAYelt($targ);
        return '$?' unless ref $pn eq 'B::PADNAME';
        my $name = eval { $pn->PV };
        return defined $name ? $name : '$?';
    }
}

1;
