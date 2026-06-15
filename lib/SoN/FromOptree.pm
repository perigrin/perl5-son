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
    use SoN::FieldInfo;

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
        my $ctx = { mode => 'main' };

        while ($$op) {
            last if $visited{$$op}++;

            my $name = $op->name;

            # dor op: $lhs // $rhs -> DefinedOr node
            if ($opmap->is_branch($name) && $name eq 'dor') {
                my $lhs = $sim->pop_node;
                # Walk the other path (RHS of //) to get the fallback value
                my $rhs_sim = $sim->snapshot;
                my $rhs_end = _walk_branch($cv, $op->other, $rhs_sim, $factory, $opmap, \%visited);
                my $rhs;
                if ($rhs_sim->stack_depth > 0) {
                    $rhs = $rhs_sim->pop_node;
                } else {
                    $rhs = $factory->make('Constant',
                        value      => undef,
                        const_type => 'undef',
                        stamp      => SoN::IR::Stamp->new(type => 'Undef'));
                }
                my $node = $factory->make('DefinedOr', inputs => [$lhs, $rhs]);
                $sim->push_node($node);
                $op = $rhs_end // $op->next;
                next;
            }

            # cond_expr op: $cond ? $true : $false -> TernaryExpr node
            if ($opmap->is_branch($name) && $name eq 'cond_expr') {
                my $cond = $sim->pop_node;
                # Walk true path (op->next) to get the true-branch value
                my $true_sim = $sim->snapshot;
                my $true_end = _walk_branch($cv, $op->next, $true_sim, $factory, $opmap, \%visited);
                my $true_val;
                if ($true_sim->stack_depth > 0) {
                    $true_val = $true_sim->pop_node;
                } else {
                    $true_val = $factory->make('Constant',
                        value      => undef,
                        const_type => 'undef',
                        stamp      => SoN::IR::Stamp->new(type => 'Undef'));
                }
                # Walk false path (op->other) to get the false-branch value
                my $false_sim = $sim->snapshot;
                my $false_end = _walk_branch($cv, $op->other, $false_sim, $factory, $opmap, \%visited);
                my $false_val;
                if ($false_sim->stack_depth > 0) {
                    $false_val = $false_sim->pop_node;
                } else {
                    $false_val = $factory->make('Constant',
                        value      => undef,
                        const_type => 'undef',
                        stamp      => SoN::IR::Stamp->new(type => 'Undef'));
                }
                my $node = $factory->make('TernaryExpr',
                    inputs => [$cond, $true_val, $false_val]);
                $sim->push_node($node);
                $op = $true_end // $false_end // $op->next;
                next;
            }

            # Branch ops: and, or
            if ($opmap->is_branch($name) && ($name eq 'and' || $name eq 'or')) {
                my $cond = $sim->pop_node;
                my $if_node = $factory->make_cfg('If', inputs => [$sim->control, $cond]);
                my $true_proj = $factory->make_cfg('Proj', inputs => [$if_node], index => 0);
                my $false_proj = $factory->make_cfg('Proj', inputs => [$if_node], index => 1);

                # Walk true path (op->next)
                my $true_sim = $sim->snapshot;
                $true_sim->set_control($true_proj);
                # For 'and', the true value is the result of continuing
                # For 'or', the false value is the result of continuing
                if ($name eq 'and') {
                    $true_sim->push_node($cond) if $name eq 'or';
                }
                my $true_end = _walk_branch($cv, $op->next, $true_sim, $factory, $opmap, \%visited);

                # Walk false path (op->other)
                my $false_sim = $sim->snapshot;
                $false_sim->set_control($false_proj);
                if ($name eq 'or') {
                    $false_sim->push_node($cond);
                }
                my $false_end = _walk_branch($cv, $op->other, $false_sim, $factory, $opmap, \%visited);

                # Merge at convergence
                my $region = $true_sim->merge($false_sim, $factory);
                $sim->set_control($region);

                # The result is on the merged stack
                if ($true_sim->stack_depth > 0) {
                    $sim->push_node($true_sim->pop_node);
                }

                # Continue from where both branches converged
                $op = $true_end // $op->next;
                next;
            }

            # Try/catch handling
            if ($name eq 'entertrycatch') {
                # Walk try body (op->other leads to catch)
                my $try_sim = $sim->snapshot;
                _walk_branch($cv, $op->next, $try_sim, $factory, $opmap, \%visited);

                # Walk catch body (op->other)
                my $catch_sim = $sim->snapshot;
                _walk_branch($cv, $op->other, $catch_sim, $factory, $opmap, \%visited);

                # Merge at leavetrycatch
                my $region = $try_sim->merge($catch_sim, $factory);
                $sim->set_control($region);

                if ($try_sim->stack_depth > 0) {
                    $sim->push_node($try_sim->pop_node);
                }

                $op = $op->next;
                # Skip ahead past the try/catch structure
                while ($$op && $op->name ne 'leavetrycatch') {
                    last if $visited{$$op}++;
                    $op = $op->next;
                }
                $op = $op->next if $$op;
                next;
            }

            # Other branch ops (iter, poptry, catch, leavetrycatch) - skip
            if ($opmap->is_branch($name) || $name eq 'poptry' || $name eq 'leavetrycatch') {
                $op = $op->next;
                next;
            }

            # Loop ops: enterloop, enteriter
            if ($name eq 'enterloop' || $name eq 'enteriter') {
                my $loop_node = $factory->make_cfg('Loop', inputs => [$sim->control]);
                $sim->set_control($loop_node);

                # Save pre-loop scope to detect modifications
                my $pre_loop_scope = $sim->scope_bindings;

                # Walk the loop body: condition + body
                # enterloop->next leads to the condition check
                my $body_op = $op->next;
                my %loop_visited;
                _walk_loop_body($cv, $body_op, $sim, $factory, $opmap, \%loop_visited, \%visited);

                # Create Phis for any variables modified during the loop
                my $post_loop_scope = $sim->scope_bindings;
                for my $targ (keys %$post_loop_scope) {
                    my $pre = $pre_loop_scope->{$targ};
                    my $post = $post_loop_scope->{$targ};
                    if (defined $pre && defined $post && $pre != $post) {
                        my $phi = $factory->make('Phi',
                            inputs => [$pre, $post],
                            region => $loop_node,
                        );
                        $sim->define($targ, $phi);
                    }
                }

                # Continue after the loop (leaveloop)
                # The B::LOOP op has lastop pointing to exit
                if ($op->can('lastop')) {
                    my $exit = $op->lastop;
                    $op = $exit;
                } else {
                    $op = $op->next;
                }
                next;
            }

            # leaveloop - end of loop, continue
            if ($name eq 'leaveloop') {
                $op = $op->next;
                next;
            }

            # Handle gv - global variable reference (for sub calls etc.)
            if ($name eq 'gv') {
                my $sv = $op->sv;
                my $gv_name = 'unknown';
                if ($$sv && $sv->isa('B::GV')) {
                    $gv_name = $sv->NAME;
                } elsif (!$$sv || $sv->isa('B::SPECIAL')) {
                    # Shared GV, look in pad
                    my $targ = $op->targ;
                    if ($targ) {
                        my $padl = $cv->PADLIST;
                        if ($$padl) {
                            my $pad_sv = $padl->ARRAYelt(1)->ARRAYelt($targ);
                            if ($$pad_sv && $pad_sv->isa('B::GV')) {
                                $gv_name = $pad_sv->NAME;
                            }
                        }
                    }
                }
                my $node = $factory->make('Constant',
                    value      => $gv_name,
                    const_type => 'string',
                    stamp      => SoN::IR::Stamp->new(type => 'Str'));
                $sim->push_node($node);
                $op = $op->next;
                next;
            }

            # Handle entersub - subroutine/method call
            if ($name eq 'entersub') {
                my $args = $sim->pop_to_mark;
                # Last arg is the CV/method, rest are arguments
                my $cv_node = $args->@* ? pop $args->@* : undef;
                my $dispatch = 'direct';
                my $call_name = 'unknown';

                # Check if preceded by method_named
                if ($cv_node && $cv_node->isa('SoN::IR::Node::Constant')) {
                    $call_name = $cv_node->value // 'unknown';
                }

                my $node = $factory->make('Call',
                    inputs        => $args->@* ? $args : [],
                    dispatch_kind => $dispatch,
                    name          => $call_name,
                );
                $sim->push_node($node);
                $op = $op->next;
                next;
            }

            # Handle method_named - push the method name as a constant
            if ($name eq 'method_named') {
                my $meth_sv = $op->meth_sv;
                my $meth_name = $$meth_sv ? $meth_sv->PV : 'unknown';
                # Pop the invocant, create a method-dispatch Call
                my $invocant = $sim->pop_node;
                my $node = $factory->make('Constant',
                    value      => $meth_name,
                    const_type => 'string',
                    stamp      => SoN::IR::Stamp->new(type => 'Str'));
                $sim->push_node($invocant);
                $sim->push_node($node);
                $op = $op->next;
                next;
            }

            # Handle return specially
            if ($name eq 'return') {
                my $args = $sim->pop_to_mark;
                my $retval = $args->@* ? $args->[-1] : $factory->make('Constant',
                    value      => undef,
                    const_type => 'undef',
                    stamp      => SoN::IR::Stamp->new(type => 'Undef'));
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
                        value      => undef,
                        const_type => 'undef',
                        stamp      => SoN::IR::Stamp->new(type => 'Undef'));
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

            # Handle match - regex match op: /pattern/flags against pad variable
            if ($name eq 'match' && $op->isa('B::PMOP')) {
                my $pattern = $op->precomp // '';
                my $flags   = _pmflags_to_str($op->pmflags);
                my $targ    = $op->targ;
                my $target  = $sim->lookup($targ);
                if (!$target) {
                    $target = _make_pad_or_field($cv, $targ, $factory);
                    $sim->define($targ, $target);
                }
                my $node = $factory->make('RegexMatch',
                    inputs  => [$target],
                    pattern => $pattern,
                    flags   => $flags,
                );
                $sim->push_node($node);
                $op = $op->next;
                next;
            }

            # Handle subst - regex substitution op: s/pattern/replacement/flags
            if ($name eq 'subst' && $op->isa('B::PMOP')) {
                my $pattern = $op->precomp // '';
                my $flags   = _pmflags_to_str($op->pmflags);
                my $targ    = $op->targ;
                my $target  = $sim->lookup($targ);
                if (!$target) {
                    $target = _make_pad_or_field($cv, $targ, $factory);
                    $sim->define($targ, $target);
                }
                # The replacement string is on the stack (pushed by const op before subst)
                my $repl_node = $sim->stack_depth > 0 ? $sim->pop_node : undef;
                my $replacement = '';
                if ($repl_node && $repl_node->isa('SoN::IR::Node::Constant')) {
                    $replacement = $repl_node->value // '';
                }
                my $node = $factory->make('RegexSubst',
                    inputs      => [$target],
                    pattern     => $pattern,
                    replacement => $replacement,
                    flags       => $flags,
                );
                $sim->push_node($node);
                $op = $op->next;
                next;
            }

            # Handle die specially: creates an Unwind CFG node, nothing pushed to stack
            if ($name eq 'die') {
                my $args = $sim->pop_to_mark;
                my $unwind = $factory->make_cfg('Unwind',
                    inputs => [$sim->control, $args->@*]);
                $sim->set_control($unwind);
                $op = $op->next;
                next;
            }

            # Common op-set (const, pad access, sassign, padsv_store, generic
            # OpMap dispatch) via the shared step handler.
            my ($next, $sig) = _step($cv, $op, $sim, $factory, $opmap, $ctx);
            if ($sig ne 'unhandled') {
                $op = $next;
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
                value      => undef,
                const_type => 'undef',
                stamp      => SoN::IR::Stamp->new(type => 'Undef'));
        }
        my $ret = $factory->make_cfg('Return',
            inputs => [$sim->control, $retval]);
        return SoN::IR::Graph->new(
            start   => $start,
            returns => [$ret],
            source  => $coderef,
        );
    }

    # Extract value, stamp, and const_type from a B::SV.
    # Returns ($value, $stamp, $const_type) where const_type is one of:
    # 'integer', 'number', 'string', or 'undef'.
    sub _extract_const ($sv) {
        return (undef, SoN::IR::Stamp->new(type => 'Undef'), 'undef')
            unless defined $sv && $$sv;

        if ($sv->isa('B::IV')) {
            return ($sv->int_value, SoN::IR::Stamp->new(type => 'Int'), 'integer');
        }
        elsif ($sv->isa('B::NV')) {
            return ($sv->NV, SoN::IR::Stamp->new(type => 'Num'), 'number');
        }
        elsif ($sv->isa('B::PV')) {
            return ($sv->PV, SoN::IR::Stamp->new(type => 'Str'), 'string');
        }
        elsif ($sv->isa('B::PVIV')) {
            # Could be either - check flags
            if ($sv->FLAGS & B::SVf_IOK()) {
                return ($sv->int_value, SoN::IR::Stamp->new(type => 'Int'), 'integer');
            }
            return ($sv->PV, SoN::IR::Stamp->new(type => 'Str'), 'string');
        }
        elsif ($sv->isa('B::PVNV')) {
            if ($sv->FLAGS & B::SVf_NOK()) {
                return ($sv->NV, SoN::IR::Stamp->new(type => 'Num'), 'number');
            }
            if ($sv->FLAGS & B::SVf_IOK()) {
                return ($sv->int_value, SoN::IR::Stamp->new(type => 'Int'), 'integer');
            }
            return ($sv->PV, SoN::IR::Stamp->new(type => 'Str'), 'string');
        }
        else {
            return (undef, SoN::IR::Stamp->new(type => 'Unknown'), 'string');
        }
    }

    # Shared op-handler core for all three walkers.
    #
    #   _step($cv, $op, $sim, $factory, $opmap, $ctx) -> ($next_op, $signal)
    #     $ctx = { mode => 'main'|'branch'|'loop' }
    #
    # Handles ONLY the common op-set that is identical across translate,
    # _walk_branch, and _walk_loop_body: pushmark, the skip-ops, const, padsv,
    # padav/padhv, argelem, sassign, padsv_store, the TARGMY-write path, and the
    # generic OpMap dispatch.  Two of these have a per-walker difference that is
    # preserved via $ctx->{mode}: the padsv_store OPpLVAL_INTRO VarDecl emission
    # (main only) and the TARGMY-write define path (loop only).
    #
    # Returns ($op->next-or-equivalent, 'handled') when it consumed the op, or
    # ($op, 'unhandled') for any op the common core does not own so the caller's
    # mode-specific switch runs.
    sub _step ($cv, $op, $sim, $factory, $opmap, $ctx) {
        my $name = $op->name;
        my $mode = $ctx->{mode};

        # Handle pushmark specially - just record the mark
        if ($name eq 'pushmark') {
            $sim->push_mark;
            return ($op->next, 'handled');
        }

        # Skip bookkeeping ops
        if ($opmap->is_skip($name)) {
            return ($op->next, 'handled');
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
            my ($value, $stamp, $const_type) = _extract_const($sv);
            my $node = $factory->make('Constant',
                value => $value, stamp => $stamp, const_type => $const_type);
            $sim->push_node($node);
            return ($op->next, 'handled');
        }

        # Handle padsv - lexical variable or field access
        if ($name eq 'padsv') {
            my $targ = $op->targ;
            my $existing = $sim->lookup($targ);
            if ($existing) {
                $sim->push_node($existing);
            } else {
                my $node = _make_pad_or_field($cv, $targ, $factory);
                $sim->define($targ, $node);
                $sim->push_node($node);
            }
            return ($op->next, 'handled');
        }

        # Handle padav/padhv - lexical array/hash variable access
        if ($name eq 'padav' || $name eq 'padhv') {
            my $targ = $op->targ;
            my $existing = $sim->lookup($targ);
            if ($existing) {
                $sim->push_node($existing);
            } else {
                my $node = _make_pad_or_field($cv, $targ, $factory);
                $sim->define($targ, $node);
                $sim->push_node($node);
            }
            return ($op->next, 'handled');
        }

        # Handle argelem -- subroutine signature parameter binding to pad slot
        if ($name eq 'argelem') {
            my $targ = $op->targ;
            my $varname = _padname($cv, $targ);
            my $node = $factory->make('PadAccess', targ => $targ, varname => $varname);
            $sim->define($targ, $node);
            $sim->push_node($node);
            return ($op->next, 'handled');
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
            return ($op->next, 'handled');
        }

        # Handle padsv_store - optimized pad assignment
        if ($name eq 'padsv_store') {
            my $value = $sim->pop_node;
            my $targ = $op->targ;
            # OPpLVAL_INTRO (128) indicates a new lexical declaration (my $x).
            # Only the main walker emits the VarDecl wrapper.
            if ($mode eq 'main' && ($op->private & 128)) {
                my $pad_node = _make_pad_or_field($cv, $targ, $factory);
                # VarDecl wraps the pad slot; value stays as the scope binding
                # so subsequent uses of the variable return the rhs value, not
                # the declaration node.  Inputs include the value so VarDecl
                # remains reachable in the graph traversal.
                $factory->make('VarDecl',
                    inputs => [$pad_node, $value],
                    scope  => 'my');
            }
            $sim->define($targ, $value);
            $sim->push_node($value);
            return ($op->next, 'handled');
        }

        # Handle ops with TARGMY (add[$i:1,6] vK/TARGMY) - writes result to pad.
        # Only the loop walker takes this path; in other modes a TARGMY op falls
        # through to the generic OpMap dispatch.
        if ($mode eq 'loop'
            && $opmap->is_known($name) && $op->can('targ') && $op->targ
            && ($op->private & 16)) {  # OPpTARGET_MY = 0x10
            my $pop_count = $opmap->pop_count($name);
            my $node_type = $opmap->node_type($name);

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
                my %extra;
                if ($node_type eq 'Call') {
                    $extra{dispatch_kind} = 'builtin';
                    $extra{name}          = $name;
                }
                my $node = $factory->make($node_type, inputs => \@inputs, %extra);
                $sim->define($op->targ, $node);
                $sim->push_node($node);
            }

            return ($op->next, 'handled');
        }

        # Generic op handling via OpMap.  Branch/loop ops are excluded so the
        # caller's mode-specific switch owns them.
        if ($opmap->is_known($name) && !$opmap->is_branch($name) && !$opmap->is_loop($name)) {
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
                my %extra;
                # Call nodes require dispatch_kind and name from the op
                if ($node_type eq 'Call') {
                    $extra{dispatch_kind} = 'builtin';
                    $extra{name}          = $name;
                }
                my $node = $factory->make($node_type, inputs => \@inputs, %extra);
                if ($push_count) {
                    $sim->push_node($node);
                }
            }

            return ($op->next, 'handled');
        }

        return ($op, 'unhandled');
    }

    # Walk a loop body (condition + body), handling the internal and/or
    sub _walk_loop_body ($cv, $op, $sim, $factory, $opmap, $loop_visited, $outer_visited) {
        my $ctx = { mode => 'loop' };
        while ($$op) {
            # Stop if we've looped back (unstack goes back to condition)
            last if $loop_visited->{$$op}++;

            my $name = $op->name;

            # unstack marks end of loop iteration - stop
            if ($name eq 'unstack') {
                last;
            }

            # leaveloop - exit the loop
            if ($name eq 'leaveloop') {
                last;
            }

            # Handle the loop condition (and/or) - walk body via other
            if (($name eq 'and' || $name eq 'or') && $sim->stack_depth > 0) {
                my $cond = $sim->pop_node;
                my $if_node = $factory->make_cfg('If', inputs => [$sim->control, $cond]);
                my $body_proj = $factory->make_cfg('Proj', inputs => [$if_node], index => 0);
                $sim->set_control($body_proj);
                # For while loops: and->other is the body, and->next is leaveloop
                $op = $op->other;
                next;
            }

            my ($next, $sig) = _step($cv, $op, $sim, $factory, $opmap, $ctx);
            if ($sig eq 'unhandled') {
                # Unknown - skip
                $op = $op->next;
                next;
            }
            $op = $next;
        }
    }

    # Walk a branch path until we hit a visited op or end
    sub _walk_branch ($cv, $op, $sim, $factory, $opmap, $visited) {
        my $ctx = { mode => 'branch' };
        while ($$op) {
            # If we've already visited this op, we've converged
            return $op if $visited->{$$op};
            $visited->{$$op}++;

            my ($next, $sig) = _step($cv, $op, $sim, $factory, $opmap, $ctx);
            if ($sig eq 'unhandled') {
                # Hit a branch or unknown - stop
                return $op;
            }
            $op = $next;
        }
        return undef;
    }

    # Create PadAccess or FieldAccess depending on whether it's a class field
    sub _make_pad_or_field ($cv, $targ, $factory) {
        my $padlist = $cv->PADLIST;
        if ($$padlist) {
            my $padnames = $padlist->ARRAYelt(0);
            my $pn = $padnames->ARRAYelt($targ);
            if (ref $pn eq 'B::PADNAME' && SoN::FieldInfo::is_field($pn)) {
                my @info = SoN::FieldInfo::field_info($pn);
                return $factory->make('FieldAccess',
                    field_index => $info[0],
                    field_stash => $info[1] // 'unknown',
                );
            }
        }
        my $varname = _padname($cv, $targ);
        return $factory->make('PadAccess', targ => $targ, varname => $varname);
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

    # Convert a PMOP pmflags bitmask to a flag string (e.g. "gi")
    sub _pmflags_to_str ($flags) {
        my $str = '';
        $str .= 'm' if $flags & 1;        # PMf_MULTILINE
        $str .= 's' if $flags & 2;        # PMf_SINGLELINE
        $str .= 'i' if $flags & 4;        # PMf_FOLD (case-insensitive)
        $str .= 'x' if $flags & 8;        # PMf_EXTENDED
        $str .= 'g' if $flags & 8388608;  # PMf_GLOBAL
        return $str;
    }
}

1;
