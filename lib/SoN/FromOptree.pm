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

    # The s///r (non-destructive) flag on a subst PMOP's pmflags. /r returns a
    # new string and leaves the source untouched, so it must not rebind the pad.
    use constant PMf_NONDESTRUCT => 0x4000000;   # 67108864

    # Result-stamp rules for computed nodes, keyed by Chalk node type. The
    # result representation of a computed value is derivable from its inputs,
    # which Chalk's backend needs but B::SoN previously only set on leaf
    # Constants. Values:
    #   'join'        - the lattice join of the input stamps (Int+Int=Int,
    #                   Int+Num=Num); used for arithmetic that preserves type.
    #   a type string - a fixed result type regardless of inputs.
    # A node type absent from this table is left unstamped (no guessing).
    my %RESULT_STAMP = (
        # Arithmetic that preserves the wider input type.
        Add      => 'join',
        Subtract => 'join',
        Multiply => 'join',
        Negate   => 'join',
        # Fixed-result arithmetic.
        Divide   => 'Num',     # Perl / is always float
        Power    => 'Num',     # Perl ** yields an NV
        Modulo   => 'Int',     # Perl % is integer
        # Bitwise / shifts are integer.
        BitAnd     => 'Int',
        BitOr      => 'Int',
        BitXor     => 'Int',
        LeftShift  => 'Int',
        RightShift => 'Int',
        Complement => 'Int',
        # String ops.
        Concat => 'Str',
        Length => 'Int',
        # Comparisons yield a boolean; the three-way <=> / cmp yield an int.
        (map { $_ => 'Boolean' } qw(
            NumEq NumLt NumGt NumLe NumGe NumNe
            StrEq StrLt StrGt StrLe StrGe StrNe
        )),
        NumCmp => 'Int',
        StrCmp => 'Int',
        # Logical negation always yields a genuine primitive boolean
        # (is_bool(!5) is true), regardless of the operand's type.
        Not => 'Boolean',
    );

    # _result_stamp($node_type, \@inputs) -> SoN::IR::Stamp or undef.
    # Derive a computed node's result stamp from its rule and input stamps.
    # Returns undef (leaving the node unstamped) when the rule is 'join' but an
    # input lacks a stamp -- an honest GAP, never a guessed type.
    sub _result_stamp ($node_type, $inputs) {
        my $rule = $RESULT_STAMP{$node_type} // return undef;
        return SoN::IR::Stamp->new(type => $rule) if $rule ne 'join';

        my @stamps = map { $_->stamp } $inputs->@*;
        return undef if grep { !defined } @stamps;

        my $acc = shift @stamps;
        $acc = SoN::IR::Stamp::join($acc, $_) for @stamps;
        return $acc;
    }

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
        # @exits accumulates every explicit return/leavesub exit as
        # { control => <cfg node>, value => <value node> }. A return inside a
        # branch arm is a control edge to the FUNCTION exit, not a value that
        # merges back into the post-branch stack -- so we collect all exits and
        # build ONE Region+Phi+Return at the end (single-exit normalization,
        # Phase 4b-1). Shared with _walk_branch via $ctx so an early return in
        # an arm records its exit instead of dying / truncating the graph.
        my @exits;
        my $main_terminated = 0;   # set when the main path hits return/leavesub
        my $pending_method;        # method name recorded by method_named for the
                                   # following entersub (method dispatch)
        my $ctx = { mode => 'main', exits => \@exits };

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

            # cond_expr op: ternary / if-else. Handled by _handle_cond_expr
            # (shared with _walk_branch so nesting recurses).
            if ($opmap->is_branch($name) && $name eq 'cond_expr') {
                $op = _handle_cond_expr($cv, $op, $sim, $factory, $opmap,
                    \%visited);
                next;
            }

            # Branch ops: and (&&), or (||). Perl compiles TWO distinct
            # constructs to the same optree op:
            #
            #  1. Value context -- `$a && $b` / `$a || $b`: SHORT-CIRCUIT
            #     OPERAND-RETURNING operators. `$a && $b` returns $a (falsy) or $b
            #     (truthy); `$a || $b` returns $a (truthy) or $b (falsy). Per
            #     corpus/mdtest/logical.md L1/L2 these lower to a single operand-
            #     returning node And(lhs, rhs) / Or(lhs, rhs); the Chalk LLVM
            #     backend expands each into the short-circuit br+phi at lowering
            #     time (the same producer/backend split DefinedOr uses for `//`).
            #
            #  2. Statement modifier -- `return 1 if $x` compiles to `$x and
            #     return 1`: op->other is a FUNCTION EXIT, not a value. This is
            #     control flow: the exit is recorded and the fall-through
            #     continues past the If on the false Proj (single-exit norm).
            #
            # The LEFT operand ($a / the guard) is already on the stack when the
            # op fires; the RIGHT arm is reached via op->other. We walk op->other
            # on a snapshot with @exits so an exit there is recorded; the 'exited'
            # signal selects control flow (case 2), otherwise a value node (case 1).
            if ($opmap->is_branch($name) && ($name eq 'and' || $name eq 'or')) {
                my $lhs = $sim->pop_node;
                my $rhs_sim = $sim->snapshot;
                # $stop_at_exit: keep the value arm's result on the stack (stop
                # before the implicit trailing leavesub) while still recording an
                # EXPLICIT return in op->other as a function exit (statement
                # modifier `return X if COND`).
                my $base_depth = $rhs_sim->stack_depth;
                # The arm always converges at THIS op's op_next (or exits);
                # stopping there keeps the rest of the sub out of the arm walk.
                my $stop_addr = ${ $op->next };
                my ($rhs_end, $rhs_sig)
                    = _walk_branch($cv, $op->other, $rhs_sim, $factory, $opmap, \%visited, \@exits, 1, $stop_addr);

                if (($rhs_sig // '') eq 'exited') {
                    # Statement-modifier / guarded exit: the op->other arm left
                    # the function. Model the guard as an If; the exit's control
                    # edge was recorded by _walk_branch. The main path continues
                    # on the Proj where the guard is NOT taken, with $lhs
                    # discarded (`return X if/unless C` yields nothing).
                    #
                    # The exit polarity differs by op:
                    #  and (`return X if C`):     exit when C true  -> continue on
                    #                             the FALSE Proj (index 1).
                    #  or  (`return X unless C`): exit when C false -> continue on
                    #                             the TRUE Proj (index 0).
                    my $if_node = $factory->make_cfg('If',
                        inputs => [$sim->control, $lhs]);
                    my $cont_index = $name eq 'and' ? 1 : 0;
                    my $cont_proj = $factory->make_cfg('Proj',
                        inputs => [$if_node], index => $cont_index);
                    $sim->set_control($cont_proj);
                    $op = $op->next;
                    next;
                }

                # Statement modifier with a side-effecting arm -- `$x = 1 if
                # $cond` compiles to `and` in VOID context (value context is
                # sK). The arm's result value is discarded; its effect is the
                # pad rebindings it made in the snapshot scope. Merge each
                # changed binding as TernaryExpr(cond, arm, base) -- arm on
                # the false side for `or`/unless -- the same value-node
                # strategy the cond_expr handler uses (the backend expands the
                # merge to br+phi).
                if (($op->flags & 3) == 1) {   # OPf_WANT == OPf_WANT_VOID
                    # Back-edge: the arm walk stopped on an op the MAIN walk
                    # already visited (the body's unstack->next re-enters the
                    # condition head) -- this is `EXPR while COND`, a pre-test
                    # loop whose graph is identical to a block while. The
                    # condition was already walked once against pre-loop
                    # bindings ($lhs; that node ends up unconsumed); re-walk
                    # condition+body as a loop from the head the back-edge
                    # targets.
                    if ($name eq 'and'
                            && defined $rhs_end && ref $rhs_end
                            && $$rhs_end != $stop_addr
                            && $visited{$$rhs_end}) {
                        _translate_while_loop($cv, $rhs_end, $sim, $factory,
                            $opmap, \%visited);
                        $op = $op->next;
                        next;
                    }
                    unless (defined $rhs_end && ref $rhs_end
                            && $$rhs_end == $stop_addr) {
                        # The arm stopped on an untranslatable op (or an
                        # `until` back-edge). Refuse loudly rather than emit
                        # a straight-line merge that silently computes one
                        # iteration.
                        die "GAP: void-context '$name' arm did not converge"
                          . " (statement-modifier loop or unhandled arm op)";
                    }
                    my $base_scope = $sim->scope_bindings;
                    my $arm_scope  = $rhs_sim->scope_bindings;
                    for my $targ (sort { $a <=> $b } keys %$arm_scope) {
                        my $base = $base_scope->{$targ};
                        my $armv = $arm_scope->{$targ};
                        # A var introduced inside the arm is scoped to the
                        # arm; only both-sides bindings merge.
                        next unless defined $base && defined $armv;
                        next if $base == $armv;
                        my @arms = $name eq 'and'
                            ? ($armv, $base)    # if:     cond ? arm : base
                            : ($base, $armv);   # unless: cond ? base : arm
                        $sim->define($targ,
                            _make_ternary($factory, $lhs, @arms));
                    }
                    $op = $op->next;
                    next;
                }

                # Value context: build the operand-returning And/Or node. The RHS
                # value is what op->other PUSHED past the pre-walk base depth (a
                # prior statement's discarded value can sit below it). A real
                # `$a && $b` always pushes a value, so the undef Constant is a
                # defensive floor (matching the dor / cond_expr handlers), not an
                # expected path.
                my $rhs = $rhs_sim->stack_depth > $base_depth
                    ? $rhs_sim->pop_node
                    : $factory->make('Constant',
                        value      => undef,
                        const_type => 'undef',
                        stamp      => SoN::IR::Stamp->new(type => 'Undef'));
                my $node_op = $name eq 'and' ? 'And' : 'Or';
                my $node = $factory->make($node_op, inputs => [$lhs, $rhs]);
                $sim->push_node($node);
                $op = $rhs_end // $op->next;
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

            # while/until loop: two-phase translation so in-loop reads rename
            # through the header Phis (see _translate_while_loop). The
            # condition head is enterloop->next.
            if ($name eq 'enterloop') {
                _translate_while_loop($cv, $op->next, $sim, $factory, $opmap, \%visited);
                # Continue after the loop; the B::LOOP op's lastop is leaveloop.
                $op = $op->can('lastop') ? $op->lastop : $op->next;
                next;
            }

            # foreach loop: only the RANGE form is lowered -- enteriter with
            # OPf_STACKED carries the two range bounds on the stack (a
            # general list is unmarked and has no counted-loop desugaring
            # yet). Non-constant bounds are refused: the synthesized
            # continuation condition needs high+1 at translation time.
            if ($name eq 'enteriter') {
                # The iteration variable's pad slot rides on the enteriter op
                # itself (LVINTRO). Implicit $_ and package-var iterators have
                # no lexical slot -- and their gv kid rides the mark stack,
                # which previously tripped the bounds check with a misleading
                # message. Check the iterator first so the GAP is truthful.
                die "GAP: foreach with a non-lexical iterator (\$_ or a"
                  . " package variable) not yet lowered\n"
                    unless $op->targ;
                die "GAP: foreach over a general list not yet lowered\n"
                    unless $op->flags & 64;   # OPf_STACKED
                my $bounds = $sim->pop_to_mark;
                die "GAP: foreach range with non-constant integer bounds not yet lowered\n"
                    unless $bounds->@* == 2
                    && !(grep {
                            !$_->isa('SoN::IR::Node::Constant')
                            || ($_->const_type // '') ne 'integer'
                        } $bounds->@*);
                _translate_foreach_range($cv, $op, $sim, $factory, $opmap,
                    \%visited, $bounds->@*);
                # Continue after the loop; the B::LOOP op's lastop is leaveloop.
                $op = $op->can('lastop') ? $op->lastop : $op->next;
                next;
            }

            # leaveloop - end of loop, continue
            if ($name eq 'leaveloop') {
                $op = $op->next;
                next;
            }

            # Handle entersub - subroutine or method call. A method dispatch is
            # signalled by a preceding method_named (recorded in $pending_method);
            # otherwise it is a direct sub call.
            if ($name eq 'entersub') {
                my $args = $sim->pop_to_mark;

                if (defined $pending_method) {
                    # Method dispatch: the first stack arg is the invocant, the
                    # rest are call arguments. class_name is statically known
                    # when the invocant is a bareword class (Class->new); for
                    # $obj->meth the invocant node (scope-resolved to its
                    # constructor Call) lets the backend infer the class.
                    my $invocant = shift $args->@*;
                    # The invocant pad read is in MOD (lvalue) context, so it
                    # arrives as a fresh PadAccess; resolve it to the variable's
                    # bound value (e.g. the constructor Call) so the dispatch
                    # names the right class.
                    if ($invocant
                        && $invocant->isa('SoN::IR::Node::PadAccess')) {
                        my $bound = $sim->lookup($invocant->targ);
                        $invocant = $bound if defined $bound;
                    }
                    # The backend requires class_name ON the method Call node.
                    # Class->new: the bareword constant invocant names the class.
                    # $obj->meth: the invocant resolves to the constructor Call,
                    # which carries the class_name -- propagate it.
                    my $class_name;
                    if ($invocant
                        && $invocant->isa('SoN::IR::Node::Constant')
                        && ($invocant->const_type // '') eq 'string') {
                        $class_name = $invocant->value;
                    }
                    elsif ($invocant
                        && $invocant->isa('SoN::IR::Node::Call')
                        && defined $invocant->class_name) {
                        $class_name = $invocant->class_name;
                    }
                    my $node = $factory->make('Call',
                        inputs        => [ $invocant, $args->@* ],
                        dispatch_kind => 'method',
                        name          => $pending_method,
                        (defined $class_name ? (class_name => $class_name) : ()),
                    );
                    $sim->push_node($node);
                    $pending_method = undef;
                    $op = $op->next;
                    next;
                }

                # Direct sub call: the last arg is the callee, the rest are args.
                my $cv_node   = $args->@* ? pop $args->@* : undef;
                my $call_name = 'unknown';
                if ($cv_node && $cv_node->isa('SoN::IR::Node::Constant')) {
                    $call_name = $cv_node->value // 'unknown';
                }
                my $node = $factory->make('Call',
                    inputs        => $args->@* ? $args : [],
                    dispatch_kind => 'direct',
                    name          => $call_name,
                );
                $sim->push_node($node);
                $op = $op->next;
                next;
            }

            # Handle method_named - record the method name for the following
            # entersub. The invocant stays on the stack (entersub consumes it).
            # The name SV can be a shared B::SPECIAL whose value lives in the
            # pad (the same indirection the const handler resolves).
            if ($name eq 'method_named') {
                my $meth_sv = $op->meth_sv;
                if ((!$$meth_sv || $meth_sv->isa('B::SPECIAL')) && $op->targ) {
                    my $padl = $cv->PADLIST;
                    $meth_sv = $padl->ARRAYelt(1)->ARRAYelt($op->targ)
                        if $$padl;
                }
                $pending_method =
                    ($$meth_sv && $meth_sv->can('PV')) ? $meth_sv->PV : 'unknown';
                $op = $op->next;
                next;
            }

            # Handle return / leavesub: record an exit and STOP this linear
            # path. The final single Return is built from @exits below (plus
            # the fall-through value if the walk reaches the sub end without an
            # explicit terminal return). On the main path this is the function
            # exit; reached inside a branch arm it is recorded by _walk_branch
            # the same way.
            if ($name eq 'return') {
                push @exits, _exit_record($sim, $factory, 'return');
                $main_terminated = 1;
                last;
            }
            if ($name eq 'leavesub' || $name eq 'leavesublv') {
                push @exits, _exit_record($sim, $factory, 'leavesub');
                $main_terminated = 1;
                last;
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
                    # s/// yields the rewritten subject, always a Str.
                    stamp       => SoN::IR::Stamp->new(type => 'Str'),
                );
                # A destructive s/// mutates the target pad in place: rebind
                # $targ so a later read of the same lexical resolves to the
                # substituted value, not the pre-subst binding (mirrors
                # padsv_store / TARGMY). The /r form (PMf_NONDESTRUCT) yields a
                # NEW string and leaves the source untouched, so it must NOT
                # rebind -- only push the result value.
                my $nondestruct = $op->pmflags & PMf_NONDESTRUCT;
                $sim->define($targ, $node) unless $nondestruct;
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

        # If the main path ran to the end of the op chain WITHOUT a terminal
        # return/leavesub (and both branch arms didn't already exit), the final
        # stack value is one more exit. A both-arms-exited body (last via the
        # and-handler) leaves $main_terminated false but @exits already holds
        # every exit and the sim has no continuation value to add.
        if (!$main_terminated && $sim->stack_depth > 0) {
            push @exits, _exit_record($sim, $factory, 'fallthrough');
        }
        elsif (!@exits) {
            # No explicit return anywhere and an empty stack: undef return.
            push @exits, _exit_record($sim, $factory, 'fallthrough');
        }

        my $ret = _build_single_exit($factory, \@exits);
        return SoN::IR::Graph->new(
            start   => $start,
            returns => [$ret],
            source  => $coderef,
        );
    }

    # _exit_record($sim, $factory, $kind) -> { control, value }
    # Capture a function-exit edge: the control node at this point and the
    # value being returned. 'return' pops to the mark (the return-list's last
    # value); 'leavesub'/'fallthrough' take the top of stack; an empty stack
    # is an undef return.
    sub _exit_record ($sim, $factory, $kind) {
        my $value;
        if ($kind eq 'return') {
            my $args = $sim->pop_to_mark;
            $value = $args->@* ? $args->[-1] : undef;
        }
        elsif ($sim->stack_depth > 0) {
            $value = $sim->pop_node;
        }
        $value //= $factory->make('Constant',
            value      => undef,
            const_type => 'undef',
            stamp      => SoN::IR::Stamp->new(type => 'Undef'));
        return { control => $sim->control, value => $value };
    }

    # _build_single_exit($factory, \@exits) -> the single Return node.
    # One exit: a plain Return. Multiple exits (early returns): merge the
    # control edges through a Region and the values through a Phi over that
    # Region, then one Return -- the single-exit shape the LLVM backend's
    # _method_body_root requires.
    sub _build_single_exit ($factory, $exits) {
        if (@$exits == 1) {
            return $factory->make_cfg('Return',
                inputs => [$exits->[0]{control}, $exits->[0]{value}]);
        }
        my $region = $factory->make_cfg('Region',
            inputs => [map { $_->{control} } @$exits]);
        my $phi = $factory->make('Phi',
            inputs => [map { $_->{value} } @$exits],
            region => $region);
        return $factory->make_cfg('Return', inputs => [$region, $phi]);
    }

    # Extract value, stamp, and const_type from a B::SV.
    # Returns ($value, $stamp, $const_type) where const_type is one of:
    # 'integer', 'number', 'string', or 'undef'.
    sub _extract_const ($sv) {
        # A constant-folded boolean comparison (1 < 2) resolves to the shared
        # PL_sv_yes / PL_sv_no SVs, which surface as a B::SPECIAL whose index is
        # 2 (yes) or 3 (no) in B::specialsv_name. Preserve the boolean-ness as a
        # Boolean Constant rather than losing it to the Unknown/string fallback.
        if (defined $sv && ref($sv) eq 'B::SPECIAL') {
            my $idx = $$sv;
            return (1,  SoN::IR::Stamp->new(type => 'Boolean'), 'boolean') if $idx == 2;
            return ('', SoN::IR::Stamp->new(type => 'Boolean'), 'boolean') if $idx == 3;
        }

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

        # Handle padrange - the optimizer's fused replacement for the pushmark
        # plus LVINTRO of a list-assignment LHS, `my (...) = @_`. The rv2av(@_)
        # RHS is elided in this form, so bind each introduced lexical positionally
        # to @_[i]. Only a mark is left on the stack; the trailing aassign pops
        # that empty mark and emits nothing. Checked before is_skip (padrange is
        # SKIP-flagged for the non-LVINTRO context-hint case).
        if ($name eq 'padrange' && ($op->flags & 0x80)) { # OPf_SPECIAL = LVINTRO range
            $sim->push_mark;
            my $first  = $op->targ;
            my $count  = $op->private & 0x7f; # OPpPADRANGE_COUNTMASK
            my $args   = _args_source($factory);
            for my $i (0 .. $count - 1) {
                my $targ = $first + $i;
                my $pad  = _make_pad_or_field($cv, $targ, $factory);
                my $idx  = $factory->make('Constant',
                    value => $i, const_type => 'integer',
                    stamp => SoN::IR::Stamp->new(type => 'Int'));
                my $elem = $factory->make('Subscript', inputs => [$args, $idx]);
                # Each list-assign target is a `my` declaration; emit a VarDecl
                # so the lexical is declared in the graph, mirroring padsv_store
                # for `my $x = ...`. The scope binding is the @_ element value.
                if ($mode eq 'main') {
                    $factory->make('VarDecl',
                        inputs => [$pad, $elem],
                        scope  => 'my');
                }
                $sim->define($targ, $elem);
            }
            # The binding is complete; the trailing aassign pops this (empty)
            # mark and emits nothing (see the aassign empty-list guard).
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

        # Handle padsv - lexical variable or field access. An lvalue padsv
        # (OPf_MOD, e.g. the LHS of `$x = 2`) must push a PadAccess so the
        # following sassign can rebind its targ; returning the currently-bound
        # value would lose the assignment target. An rvalue padsv returns the
        # bound value (the variable's current value).
        if ($name eq 'padsv') {
            my $targ = $op->targ;
            my $is_lvalue = ($op->flags & 32); # OPf_MOD
            my $existing = $sim->lookup($targ);
            if ($existing && !$is_lvalue) {
                $sim->push_node($existing);
            } else {
                my $node = _make_pad_or_field($cv, $targ, $factory);
                # Only seed the binding when the slot has none yet. An lvalue
                # padsv over an already-bound slot must NOT clobber the binding:
                # a plain `$x = 2` rebinds via the following sassign, while a
                # compound `$x += 2` reads the current bound value first.
                $sim->define($targ, $node) unless defined $existing;
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

        # Handle gv - global variable reference. Pushes the GV NAME as a
        # string Constant: an entersub consumes it as the callee name. An
        # rv2sv over it (a package scalar read) pops and replaces it below.
        if ($name eq 'gv') {
            my $gv = _op_gv($cv, $op);
            my $node = $factory->make('Constant',
                value      => $gv ? $gv->NAME : 'unknown',
                const_type => 'string',
                stamp      => SoN::IR::Stamp->new(type => 'Str'));
            $sim->push_node($node);
            return ($op->next, 'handled');
        }

        # Handle gvsv (peep-fused) and rv2sv-over-gv (canonical): a package
        # scalar read. A numbered capture var ($1..) reads a group of the
        # last regex match (corpus host.md H1/H2: RegexCapture(match, n)
        # :Str); any other package scalar is a StashAccess named from its GV.
        if ($name eq 'gvsv'
            || ($name eq 'rv2sv' && $op->can('first') && $op->first->name eq 'gv')) {
            my $gv_op = $name eq 'gvsv' ? $op : $op->first;
            # rv2sv's gv kid already pushed its name Constant; discard it.
            $sim->pop_node if $name eq 'rv2sv';
            my $gv = _op_gv($cv, $gv_op);
            my $gv_name = $gv && $gv->NAME;
            die "GAP: package scalar read with an unresolvable GV not yet lowered\n"
                unless defined $gv_name;
            if ($gv_name =~ /^[1-9][0-9]*$/) {
                my $match = $sim->last_match
                    // die "GAP: capture \$$gv_name read with no preceding match in scope\n";
                my $node = $factory->make('RegexCapture',
                    inputs => [$match],
                    n      => 0 + $gv_name,
                    stamp  => SoN::IR::Stamp->new(type => 'Str'));
                $sim->push_node($node);
            }
            else {
                my $node = $factory->make('StashAccess',
                    stash_name => $gv->STASH->NAME,
                    var_name   => $gv_name);
                $sim->push_node($node);
            }
            return ($op->next, 'handled');
        }

        # Any other rv2sv is a scalar dereference this walker does not model.
        if ($name eq 'rv2sv') {
            die "GAP: scalar dereference (rv2sv over a non-gv) not yet lowered\n";
        }

        # Handle match - regex match op. A literal pattern (precomp) is a
        # RegexMatch; a runtime pattern ($s =~ $re) has no precomp -- its
        # regcomp kid is transparent (OpMap SKIP), leaving the matcher value
        # on the stack, and the application is a Match(subject, matcher)
        # node (corpus regex.md R2; the backend resolves a qr constant
        # statically). Either way the node is recorded as the last match so
        # a following $N read can wire to it.
        if ($name eq 'match' && $op->isa('B::PMOP')) {
            my $pattern = $op->precomp;
            my $targ    = $op->targ;
            my $target  = $sim->lookup($targ);
            if (!$target) {
                $target = _make_pad_or_field($cv, $targ, $factory);
                $sim->define($targ, $target);
            }
            my $node;
            if (defined $pattern) {
                $node = $factory->make('RegexMatch',
                    inputs  => [$target],
                    pattern => $pattern,
                    flags   => _pmflags_to_str($op->pmflags),
                );
            }
            else {
                $node = $factory->make('Match',
                    inputs => [$target, $sim->pop_node],
                    stamp  => SoN::IR::Stamp->new(type => 'Boolean'),
                );
            }
            $sim->set_last_match($node);
            $sim->push_node($node);
            return ($op->next, 'handled');
        }

        # Handle qr// - a compiled-regex literal. It is a first-class
        # matcher VALUE (corpus regex.md R2): a Constant of const_type
        # 'regex' carrying the pattern. A later =~ applies it.
        if ($name eq 'qr' && $op->isa('B::PMOP')) {
            my $pattern = $op->precomp
                // die "GAP: qr// with a runtime-interpolated pattern not yet lowered\n";
            my $node = $factory->make('Constant',
                value      => $pattern,
                const_type => 'regex',
            );
            $sim->push_node($node);
            return ($op->next, 'handled');
        }

        # Handle undef -- perl compiles `my $a = undef` to a single undef op
        # with LVINTRO+TARGMY (the sassign is nulled), and a bare undef value
        # to the same op with no targ. Either way the value is the Undef
        # Constant (corpus logical.md L3b). undef(EXPR) has kids and mutates
        # its operand -- not modeled yet.
        if ($name eq 'undef') {
            die "GAP: undef(EXPR) not yet lowered\n" if $op->flags & 4; # OPf_KIDS
            my $node = _undef_constant($factory);
            if ($op->can('targ') && $op->targ && ($op->private & 16)) { # OPpTARGET_MY
                my $targ = $op->targ;
                if ($mode eq 'main' && ($op->private & 128)) { # OPpLVAL_INTRO
                    my $pad_node = _make_pad_or_field($cv, $targ, $factory);
                    $factory->make('VarDecl',
                        inputs => [$pad_node, $node],
                        scope  => 'my');
                }
                $sim->define($targ, $node);
            }
            $sim->push_node($node);
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

        # Handle aelem/helem - array/hash element access (canonical, unfused).
        # The container and index are on the stack (index on top). An lvalue
        # access (OPf_MOD, the LHS of `$a[0] = ...`) yields a Subscript that the
        # following sassign stores into. An rvalue read resolves to the most
        # recent element store for (container, index) if one exists, so that a
        # read after a store sees the stored value; otherwise it is a Subscript.
        if ($name eq 'aelem' || $name eq 'helem') {
            my $index     = $sim->pop_node;
            my $container = $sim->pop_node;
            my $is_lvalue = ($op->flags & 32); # OPf_MOD
            my $key       = _elem_key($container, $index);

            if (!$is_lvalue && defined $key
                && exists $ctx->{elem_store}{$key}) {
                $sim->push_node($ctx->{elem_store}{$key});
            }
            else {
                my $sub = $factory->make('Subscript', inputs => [$container, $index]);
                $sim->push_node($sub);
            }
            return ($op->next, 'handled');
        }

        # Handle pre/post increment and decrement. These are read-modify-write
        # ops on an lvalue pad: read the current value, add/subtract 1, rebind
        # the target, and push the result. A PRE op (++$i / --$i) yields the NEW
        # value; a POST op ($i++ / $i--) yields the OLD value. Perl collapses a
        # void-context $i++ to preinc, so the K2 corpus case (read after) is
        # correctly the new value either way.
        if ($name =~ /^(i_)?(pre|post)(inc|dec)$/) {
            my $dir      = $3;          # inc | dec
            my $is_post  = ($2 eq 'post');
            my $old      = $sim->pop_node;

            # Resolve an lvalue PadAccess to the variable's current bound value
            # so the arithmetic carries a real (stamped) input.
            my $targ;
            if ($old->isa('SoN::IR::Node::PadAccess')) {
                $targ  = $old->targ;
                my $bound = $sim->lookup($targ);
                $old = $bound if defined $bound;
            }

            my $one = $factory->make('Constant',
                value => 1, const_type => 'integer',
                stamp => SoN::IR::Stamp->new(type => 'Int'));
            my $node_type = ($dir eq 'inc') ? 'Add' : 'Subtract';
            my $stamp = _result_stamp($node_type, [$old, $one]);
            my %extra = defined $stamp ? (stamp => $stamp) : ();
            my $new = $factory->make($node_type, inputs => [$old, $one], %extra);

            $sim->define($targ, $new) if defined $targ;
            # Pre yields the new value; post yields the old value.
            $sim->push_node($is_post ? $old : $new);
            return ($op->next, 'handled');
        }

        # Handle bare shift/pop - the @_ operand is implicit (nullary op).
        # `shift @arr` has OPf_KIDS set and pushes its array operand normally;
        # bare `shift` is nullary, so supply the implicit @_ source here and let
        # the generic OpMap Call dispatch consume it.
        if (($name eq 'shift' || $name eq 'pop') && !($op->flags & 4)) { # OPf_KIDS
            $sim->push_node(_args_source($factory));
            # fall through to generic dispatch below (do not return)
        }

        # Handle sassign - scalar assignment
        if ($name eq 'sassign') {
            # Perl pushes the RHS (value) first, then the LHS (target), so the
            # target is on top: pop it first, then the value.
            my $target = $sim->pop_node;
            my $value  = $sim->pop_node;
            # If target is a PadAccess, update the scope binding.
            if ($target->isa('SoN::IR::Node::PadAccess')) {
                $sim->define($target->targ, $value);
                $sim->push_node($value);
            }
            # An element store (`$a[0] = 42`): the target is a Subscript lvalue.
            # Emit Assign(Subscript, value) and record the store so a later read
            # of the same element returns the stored value. The assignment's
            # result value is the stored value, so push that as the result.
            elsif ($target->isa('SoN::IR::Node::Subscript')) {
                $factory->make('Assign', inputs => [$target, $value]);
                my ($container, $index) = $target->inputs->@*;
                my $key = _elem_key($container, $index);
                $ctx->{elem_store}{$key} = $value if defined $key;
                $sim->push_node($value);
            }
            else {
                $sim->push_node($value);
            }
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

        # Handle multiconcat for the `.=` const-append case (corpus S4). The op
        # is `$s .= "lit"`: a multiconcat with OPpMULTICONCAT_APPEND (0x40) and
        # nargs == 0 (all parts constant). aux_list is [nargs, const_str, len];
        # the result is Concat($s, const_str) stored back to the targ slot.
        # Dynamic parts (nargs > 0, e.g. `$s .= $t`) are not yet modeled.
        if ($name eq 'multiconcat'
            && ($op->private & 0x40)            # OPpMULTICONCAT_APPEND
            && $op->can('aux_list')) {
            my @aux   = $op->aux_list($cv);
            my $nargs = $aux[0];
            if (defined $nargs && $nargs == 0 && @aux >= 2) {
                my $lit  = ref $aux[1] ? eval { $aux[1]->PV } : $aux[1];
                my $targ = $op->targ;
                my $cur  = $sim->lookup($targ);
                if (defined $cur && defined $lit) {
                    my $rhs = $factory->make('Constant',
                        value => $lit, const_type => 'string',
                        stamp => SoN::IR::Stamp->new(type => 'Str'));
                    my $cat = $factory->make('Concat',
                        inputs => [$cur, $rhs],
                        stamp  => SoN::IR::Stamp->new(type => 'Str'));
                    $sim->define($targ, $cat);
                    $sim->push_node($cat);
                    return ($op->next, 'handled');
                }
            }
            # Fall through: dynamic / multi-part multiconcat is not yet handled.
        }

        # Handle ops with TARGMY (add[$i:1,6] vK/TARGMY) - the op writes its
        # result in-place to its targ slot. This is the canonical shape of a
        # self-assign (`$x = $x + 1`), a field write (`$n = $n + 1`), and other
        # store-back-to-self forms. Rebind the targ so a later read of that slot
        # returns the new value.
        if ($opmap->is_known($name) && $op->can('targ') && $op->targ
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
                my $stamp = _result_stamp($node_type, \@inputs);
                $extra{stamp} = $stamp if defined $stamp;
                my $node = $factory->make($node_type, inputs => \@inputs, %extra);
                $sim->define($op->targ, $node);
                $sim->push_node($node);
            }

            return ($op->next, 'handled');
        }

        # Handle aassign whose targets were already bound by a preceding padrange
        # (`my (...) = @_`): the mark is empty because padrange consumed the LHS
        # and the @_ RHS was elided. Pop the empty mark and emit nothing rather
        # than a stray, dead Assign node. Real list-assigns with values on the
        # stack fall through to the generic dispatch below.
        if ($name eq 'aassign') {
            # The LHS list is the most recent mark; the RHS list (if present) is
            # the mark before it. Perl lays out aassign as
            # pushmark RHS... pushmark LHS..., so popping to the last mark yields
            # the LHS, then popping to the prior mark yields the RHS.
            my $lhs = $sim->pop_to_mark;

            # `my (...) = @_` with a padrange-bound LHS leaves an empty mark and
            # no RHS; emit nothing (the bind already happened).
            if (!$lhs->@*) {
                return ($op->next, 'handled');
            }

            # Array/hash construction: `my @a = (1,2,3)` / `my %h = (k=>0)`.
            # The LHS is a single padav/padhv; bind it to an ArrayRef/HashRef of
            # the RHS values so later element access has a real container.
            if (@$lhs == 1
                && $lhs->[0]->isa('SoN::IR::Node::PadAccess')
                && $sim->has_mark) {
                my $target = $lhs->[0];
                my $rhs    = $sim->pop_to_mark;
                my $sigil  = substr($target->varname, 0, 1);
                if ($sigil eq '@') {
                    my $aref = $factory->make('ArrayRef', inputs => [$rhs->@*]);
                    $sim->define($target->targ, $aref);
                    $sim->push_node($aref);
                    return ($op->next, 'handled');
                }
                elsif ($sigil eq '%') {
                    my $href = $factory->make('HashRef', inputs => [$rhs->@*]);
                    $sim->define($target->targ, $href);
                    $sim->push_node($href);
                    return ($op->next, 'handled');
                }
            }

            # Fallback: a generic list assignment.
            my $node = $factory->make('Assign', inputs => [$lhs->@*]);
            $sim->push_node($node);
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
                # Compound assignment (`$x += 2`): a binary arithmetic op whose
                # FIRST operand is an lvalue (OPf_MOD) pad read is a read-modify-
                # write. The lvalue padsv pushed a fresh PadAccess (Commit A's
                # rule for assignment targets), but the read half of `+=` needs
                # the variable's CURRENT value: resolve it to the bound value so
                # the op carries a real (stamped) input. `$y = $x + 2` does not
                # match -- its $x read is not in modify context.
                my $is_compound =
                       @inputs >= 1
                    && $inputs[0]->isa('SoN::IR::Node::PadAccess')
                    && $op->can('first')
                    && $op->first->name =~ /^padsv|^padav|^padhv/
                    && ($op->first->flags & 32); # OPf_MOD

                my $lvalue_targ;
                if ($is_compound) {
                    $lvalue_targ = $inputs[0]->targ;
                    my $bound = $sim->lookup($lvalue_targ);
                    $inputs[0] = $bound if defined $bound;
                }

                my $stamp = _result_stamp($node_type, \@inputs);
                $extra{stamp} = $stamp if defined $stamp;
                my $node = $factory->make($node_type, inputs => \@inputs, %extra);

                # Rebind the target to the result so a later read sees the new
                # value.
                if ($is_compound) {
                    $sim->define($lvalue_targ, $node);
                }

                if ($push_count) {
                    $sim->push_node($node);
                }
            }

            return ($op->next, 'handled');
        }

        return ($op, 'unhandled');
    }

    # Walk a loop body (condition + body), handling the internal and/or
    # Translate a while loop (enterloop) to the corpus Loop/Phi contract:
    # Loop(entry) IS the header (no If inside it); Proj(loop,0) is the body
    # edge, Proj(loop,1) the exit edge, Region(exit Proj) the post-loop
    # control; every loop-carried variable reads through a header Phi
    # (inputs[0]=init, inputs[1]=backedge, region=Loop) so the condition and
    # body see the current iteration's value, not the pre-loop bindings.
    #
    # The body computes the back-edge values FROM the Phis, so the Phis must
    # exist before the body is walked -- but which variables need one is only
    # known from the body. Two-phase: (1) SCOUT the condition+body on a
    # throwaway sim and factory to discover the mutated pad slots (scout
    # nodes never reach the real graph); (2) create a header Phi per mutated
    # slot, rebind, walk for real, then patch each Phi's back-edge and stamp.
    # Scout a loop's ops on an insulated sim (own factory, own Start,
    # placeholder bindings) to discover which pad slots the walk mutates.
    # Constructing a scout node over a real node would leak it into the real
    # graph through the use-def consumer edge registered at construction, so
    # no real node is shared. $extra_targs introduces slots that do not exist
    # pre-loop (a foreach induction variable). Returns the sorted mutated
    # pre-existing slots.
    sub _scout_mutated_targs ($cv, $start_op, $sim, $opmap, $extra_targs = []) {
        my $scout_factory = SoN::IR::NodeFactory->new();
        my $scout_sim     = SoN::FromOptree::StackSim->new(
            control => $scout_factory->make_cfg('Start'));
        my %placeholder;
        for my $targ (keys $sim->scope_bindings->%*, $extra_targs->@*) {
            my $ph = $scout_factory->make_unique('Constant',
                value => 'scout', const_type => 'string');
            $placeholder{$targ} = $ph;
            $scout_sim->define($targ, $ph);
        }
        _walk_loop_body($cv, $start_op, $scout_sim, $scout_factory, $opmap, {}, {});
        my $scout_scope = $scout_sim->scope_bindings;
        my %extra = map { $_ => 1 } $extra_targs->@*;
        return [ sort { $a <=> $b }
            grep {
                !$extra{$_}
                && defined $scout_scope->{$_}
                && $scout_scope->{$_} != $placeholder{$_}
            } keys %placeholder ];
    }

    # Create a loop header Phi for a slot (make_unique: two Phis with the
    # same init are distinct recurrences until their back-edges wire). The
    # Phi carries its init's stamp so the body's join-stamped nodes, which
    # read the Phi, can derive theirs; _patch_loop_phi verifies the
    # back-edge does not widen it.
    sub _make_loop_phi ($factory, $loop_node, $init) {
        return $factory->make_unique('Phi',
            inputs => [$init],
            region => $loop_node,
            (defined $init->stamp ? (stamp => $init->stamp) : ()));
    }

    # Wire a loop Phi's back-edge, re-point the slot at the Phi (the body
    # walk rebound it to the last in-loop value; post-loop reads must see
    # the Phi -- its value when the condition finally failed), and verify
    # the stamp: a back-edge that widens the init-derived stamp would need
    # a fixpoint re-walk, and an unstamped back-edge means the init stamp
    # cannot be trusted past the first iteration -- refuse or unstamp
    # honestly, no guessing.
    sub _patch_loop_phi ($sim, $targ, $phi, $post) {
        $phi->set_backedge($post);
        $sim->define($targ, $phi);
        my $init = $phi->inputs->[0];
        if (defined $init->stamp && defined $post->stamp) {
            my $join = SoN::IR::Stamp::join($init->stamp, $post->stamp);
            die "GAP: loop-carried type widening not yet lowered\n"
                if defined $phi->stamp && $join->type ne $phi->stamp->type;
            $phi->set_stamp($join);
        }
        elsif (defined $phi->stamp) {
            # The body was already stamped against this Phi's optimistic
            # init stamp; merely un-stamping the Phi here leaves those stale
            # stamps contaminating sibling Phi joins (a type-level
            # miscompile). Refuse until fixpoint restamping exists.
            die "GAP: loop-carried value loses its stamp (unstamped"
              . " back-edge); fixpoint restamping not yet lowered\n";
        }
        return;
    }

    # The backend recovers the loop condition as "the comparison consuming a
    # header Phi" (its strategy-2 fallback; the producer does not yet wire the
    # control edge strategy 1 wants). That is only sound when exactly ONE such
    # comparison exists -- a second one (a body comparison on a loop-carried
    # value) makes the choice arbitrary, and review reproduced the backend
    # picking a decoy. Refuse until the condition is structurally wired.
    my %ICMP_OP = map { $_ => 1 } qw(NumEq NumLt NumGt NumLe NumGe NumNe);
    sub _assert_unambiguous_condition (@phis) {
        my %cmp;
        for my $phi (@phis) {
            for my $c ($phi->consumers->@*) {
                $cmp{$c->id} = 1 if $ICMP_OP{$c->operation};
            }
        }
        die "GAP: ambiguous loop condition (multiple comparisons consume"
          . " header Phis) not yet lowered\n"
            if keys %cmp > 1;
    }

    # The condition segment runs once more than the body (the failing test
    # still applies its side effects), which this translation cannot represent
    # -- and on the postfix path the main walk has already applied one
    # evaluation's mutations to the live scope, contaminating the Phi inits.
    # Scout the condition ops alone on an insulated sim (stopping at the
    # and/or that closes the condition) and refuse loudly if they rebind any
    # pad slot.
    sub _assert_pure_condition ($cv, $cond_start, $sim, $opmap) {
        my $probe = $cond_start;
        my %probe_seen;
        $probe = $probe->next
            while $$probe && !$probe_seen{$$probe}++
                && $probe->name ne 'and' && $probe->name ne 'or';
        return unless $$probe
            && ($probe->name eq 'and' || $probe->name eq 'or');

        my $cond_factory = SoN::IR::NodeFactory->new();
        my $cond_sim     = SoN::FromOptree::StackSim->new(
            control => $cond_factory->make_cfg('Start'));
        my %placeholder;
        for my $targ (keys $sim->scope_bindings->%*) {
            my $ph = $cond_factory->make_unique('Constant',
                value => 'scout', const_type => 'string');
            $placeholder{$targ} = $ph;
            $cond_sim->define($targ, $ph);
        }
        _walk_branch($cv, $cond_start, $cond_sim, $cond_factory, $opmap,
            {}, undef, 0, $$probe);
        my $after = $cond_sim->scope_bindings;
        for my $targ (keys %placeholder) {
            next unless defined $after->{$targ};
            die "GAP: side-effecting loop condition not yet lowered\n"
                if $after->{$targ} != $placeholder{$targ};
        }
        return;
    }

    sub _translate_while_loop ($cv, $cond_start, $sim, $factory, $opmap, $visited) {
        _assert_pure_condition($cv, $cond_start, $sim, $opmap);

        # Phase 1: scout the condition + body for mutated pad slots.
        my $pre_scope = $sim->scope_bindings;
        my $mutated = _scout_mutated_targs($cv, $cond_start, $sim, $opmap);

        # Phase 2: the loop header and its Phis.
        my $loop_node = $factory->make_cfg('Loop', inputs => [$sim->control]);
        $sim->set_control($loop_node);
        my %phis;
        for my $targ ($mutated->@*) {
            my $phi = _make_loop_phi($factory, $loop_node, $pre_scope->{$targ});
            $phis{$targ} = $phi;
            $sim->define($targ, $phi);
        }

        # Phase 3: the real walk (condition + body against the Phi bindings).
        my $exit_proj = _walk_loop_body($cv, $cond_start, $sim, $factory,
            $opmap, {}, $visited, $loop_node);
        die "GAP: loop without a lowerable condition\n"
            unless defined $exit_proj;

        # Phase 4: patch back-edges and stamps.
        my $post_scope = $sim->scope_bindings;
        _patch_loop_phi($sim, $_, $phis{$_}, $post_scope->{$_}) for $mutated->@*;
        _assert_unambiguous_condition(values %phis);

        # Phase 5: post-loop control continues on the exit edge.
        my $exit_region = $factory->make_cfg('Region', inputs => [$exit_proj]);
        $sim->set_control($exit_region);
        return;
    }

    # Translate a range foreach (enteriter with OPf_STACKED constant bounds)
    # to the corpus counted-loop contract (control-flow.md D3): induction Phi
    # init=low with a synthesized +1 step, continuation NumGt(high+1, phi),
    # body walked with the induction bound to the Phi, and the while-loop
    # Loop/Proj/Region skeleton. The unstack/iter/and condition ops are not
    # walked -- the induction is synthesized here -- and the main walker
    # resumes at the B::LOOP lastop (leaveloop).
    sub _translate_foreach_range ($cv, $enteriter, $sim, $factory, $opmap, $visited, $low, $high) {
        my $i_targ = $enteriter->targ;

        # Locate the body: enteriter->next is the iteration unstack, followed
        # by iter, then the and whose other-branch is the body.
        my $it = $enteriter->next;
        $it = $it->next while $$it && $it->name ne 'iter';
        die "GAP: foreach without an iter op\n" unless $$it;
        my $and_op = $it->next;
        die "GAP: foreach without an and condition\n"
            unless $$and_op && $and_op->name eq 'and';
        my $body_start = $and_op->other;

        # Phase 1: scout the body ($i is introduced by enteriter itself, so
        # it rides as an extra slot and is excluded from the mutated set --
        # it gets the induction Phi, not a carried-value Phi).
        my $pre_scope = $sim->scope_bindings;
        my $mutated = _scout_mutated_targs($cv, $body_start, $sim, $opmap, [$i_targ]);

        # Phase 2: header -- induction Phi plus one Phi per mutated slot.
        my $loop_node = $factory->make_cfg('Loop', inputs => [$sim->control]);
        $sim->set_control($loop_node);
        my $i_phi = _make_loop_phi($factory, $loop_node, $low);
        $sim->define($i_targ, $i_phi);
        my %phis;
        for my $targ ($mutated->@*) {
            my $phi = _make_loop_phi($factory, $loop_node, $pre_scope->{$targ});
            $phis{$targ} = $phi;
            $sim->define($targ, $phi);
        }

        # Continuation condition: loop while i <= high, authored as
        # NumGt(high+1, i_phi) per the corpus D3 ir-block. The backend
        # recovers it as the comparison consuming a header Phi; it needs no
        # consumer here. high+1 at IV_MAX overflows to an NV and wraps in
        # the emitted i64 (zero iterations, silently) -- refuse that edge.
        die "GAP: foreach range bound at IV_MAX not yet lowered\n"
            if $high->value >= 9223372036854775807;
        my $bound = $factory->make('Constant',
            value      => $high->value + 1,
            const_type => 'integer',
            stamp      => SoN::IR::Stamp->new(type => 'Int'));
        $factory->make('NumGt',
            inputs => [$bound, $i_phi],
            stamp  => SoN::IR::Stamp->new(type => 'Boolean'));

        # Phase 3: body under Proj(loop,0); exit on Proj(loop,1).
        my $body_proj = $factory->make_cfg('Proj', inputs => [$loop_node], index => 0);
        my $exit_proj = $factory->make_cfg('Proj', inputs => [$loop_node], index => 1);
        $sim->set_control($body_proj);
        _walk_loop_body($cv, $body_start, $sim, $factory, $opmap, {}, $visited);

        # Phase 4: back-edges. The induction step is synthesized (+1); the
        # carried slots patch exactly like the while loop.
        my $one = $factory->make('Constant',
            value => 1, const_type => 'integer',
            stamp => SoN::IR::Stamp->new(type => 'Int'));
        my $i_next = $factory->make('Add',
            inputs => [$i_phi, $one],
            stamp  => _result_stamp('Add', [$i_phi, $one]));
        $i_phi->set_backedge($i_next);
        my $post_scope = $sim->scope_bindings;
        _patch_loop_phi($sim, $_, $phis{$_}, $post_scope->{$_}) for $mutated->@*;
        _assert_unambiguous_condition($i_phi, values %phis);

        # Phase 5: post-loop control continues on the exit edge.
        my $exit_region = $factory->make_cfg('Region', inputs => [$exit_proj]);
        $sim->set_control($exit_region);
        return;
    }

    # Walk a loop's condition + body ops. With $loop_node (the real walk of
    # _translate_while_loop) the condition builds Projs directly on the Loop
    # per the corpus contract and the exit Proj is returned; without it (the
    # scout walk, whose nodes are throwaway) the legacy If shape is kept --
    # the binding effects are identical either way, which is all the scout
    # measures.
    sub _walk_loop_body ($cv, $op, $sim, $factory, $opmap, $loop_visited, $outer_visited, $loop_node = undef) {
        my $ctx = { mode => 'loop' };
        my $exit_proj;
        my $condition_fired = 0;
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

            # A function exit inside the loop body cannot be represented yet
            # (its control edge leaves the loop mid-iteration); walking
            # through it produced silently wrong graphs, so refuse loudly.
            if ($name eq 'return' || $name eq 'leavesub' || $name eq 'leavesublv') {
                die "GAP: function exit inside a loop body not yet lowered\n";
            }

            # Loop-control ops re-route the iteration; walking past one
            # produced silently wrong graphs (a dropped `last` ran the loop
            # to completion). Refuse loudly.
            if ($name eq 'last' || $name eq 'next' || $name eq 'redo') {
                die "GAP: loop control ($name) inside a loop body not yet lowered\n";
            }

            # Nested control structure in a body is only translated by the
            # MAIN walker; skipping it here emitted corrupt graphs (a nested
            # loop minted Projs on the OUTER Loop and truncated the walk; a
            # skipped if/else dropped its arms entirely). Refuse loudly. The
            # loop's own and/or condition is handled below.
            if ($name eq 'enterloop' || $name eq 'enteriter'
                || ($opmap->is_branch($name) && $name ne 'and' && $name ne 'or')) {
                die "GAP: $name inside a loop body not yet lowered\n";
            }

            # Handle the loop condition (and/or) - walk body via other
            if (($name eq 'and' || $name eq 'or') && $sim->stack_depth > 0) {
                # A second and/or here is NOT the loop condition -- it is a
                # nested logical/modifier construct this walker cannot
                # translate (it would mint a second Proj pair on the Loop).
                die "GAP: nested and/or inside a loop body not yet lowered\n"
                    if $condition_fired++;
                my $cond = $sim->pop_node;
                if (defined $loop_node) {
                    # The backend recovers the condition as the comparison
                    # consuming a header Phi; $cond needs no consumer here.
                    # An `or` condition (until) would need the negated sense.
                    die "GAP: until (or-condition) loop not yet lowered\n"
                        if $name eq 'or';
                    my $body_proj = $factory->make_cfg('Proj',
                        inputs => [$loop_node], index => 0);
                    $exit_proj = $factory->make_cfg('Proj',
                        inputs => [$loop_node], index => 1);
                    $sim->set_control($body_proj);
                }
                else {
                    my $if_node = $factory->make_cfg('If', inputs => [$sim->control, $cond]);
                    my $body_proj = $factory->make_cfg('Proj', inputs => [$if_node], index => 0);
                    $sim->set_control($body_proj);
                }
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
        return $exit_proj;
    }

    # Both arms of a cond_expr rejoin at the op AFTER the construct, but that
    # op is not derivable from the cond_expr itself (op_next IS the false
    # arm). Scan each arm's op_next chain and take the first address the two
    # share: a linear op_next scan follows SOME path through any nested
    # branches, and all paths rejoin, so the join lies on every chain.
    # Returns 0 when no common op is found (degenerate/cyclic chains).
    sub _find_join_addr ($a_start, $b_start) {
        my %a_seen;
        for (my $op = $a_start; $$op && !$a_seen{$$op}; $op = $op->next) {
            $a_seen{$$op} = 1;
        }
        my %b_seen;
        for (my $op = $b_start; $$op && !$b_seen{$$op}; $op = $op->next) {
            return $$op if $a_seen{$$op};
            $b_seen{$$op} = 1;
        }
        return 0;
    }

    sub _undef_constant ($factory) {
        return $factory->make('Constant',
            value      => undef,
            const_type => 'undef',
            stamp      => SoN::IR::Stamp->new(type => 'Undef'));
    }

    # A merge's type is the join of its two ARM stamps -- the condition never
    # contributes (a Boolean guard does not make the value a Boolean). Left
    # unstamped when either arm is (honest GAP, no guessing); the backend
    # requires an explicit repr on a ternary consumed as another's arm.
    sub _make_ternary ($factory, $cond, $true_val, $false_val) {
        my %args = (inputs => [$cond, $true_val, $false_val]);
        if (defined $true_val->stamp && defined $false_val->stamp) {
            $args{stamp} = SoN::IR::Stamp::join(
                $true_val->stamp, $false_val->stamp);
        }
        return $factory->make('TernaryExpr', %args);
    }

    # cond_expr: $cond ? $true : $false, and the statement form
    # `if (...) {...} else {...}` (a VOID cond_expr). op->next reaches the
    # FALSE arm and op->other the TRUE arm (probe-confirmed); TernaryExpr
    # wants inputs[1]=true, inputs[2]=false. Each arm walks on a snapshot
    # with a stop at the join op so it cannot consume the rest of the sub.
    #
    # Value context: the construct's value is what each arm PUSHES past the
    # pre-walk base depth (a prior statement's discarded value can sit below).
    # Void context: the value is discarded; the effect is the pad rebinds the
    # arms made -- each slot changed in EITHER arm rebinds to
    # TernaryExpr(cond, true_binding, false_binding), falling back to the
    # pre-construct binding (or undef: an if/else may initialize a declared-
    # but-unassigned `my $x`) for the arm that left it alone.
    #
    # Called from the main walk AND from _walk_branch, so nested ternaries /
    # if-else inside an arm recurse instead of degrading the arm value to the
    # inner condition. Returns the op where translation continues.
    sub _handle_cond_expr ($cv, $op, $sim, $factory, $opmap, $visited) {
        # List context would need per-arm value LISTS; the scalar path below
        # pops exactly one value per arm and silently mistranslated
        # `my @a = $c ? (1,2) : (3,4)`. Refuse loudly.
        die "GAP: list-context ternary not yet lowered\n"
            if ($op->flags & 3) == 3;   # OPf_WANT == OPf_WANT_LIST

        my $cond = $sim->pop_node;
        my $join_addr = _find_join_addr($op->other, $op->next) || undef;

        my $base_depth = $sim->stack_depth;
        my $walk_arm = sub ($start) {
            my $arm_sim = $sim->snapshot;
            # A local exit accumulator so an explicit `return` in the arm is
            # DETECTED (with none, the walk stepped through it and silently
            # dropped the exit -- the function then returned the merge).
            # A one-sided exit needs real control threading; refuse loudly.
            my @arm_exits;
            my ($end, $sig) = _walk_branch($cv, $start, $arm_sim, $factory,
                $opmap, $visited, \@arm_exits, 1, $join_addr);
            die "GAP: function exit inside an if/else arm not yet lowered\n"
                if ($sig // '') eq 'exited';
            # An arm stopping anywhere OTHER than the join hit an op the
            # walker cannot translate -- and it marked that op visited, so
            # the main walk would terminate there too, silently dropping
            # everything after the if/else. Refuse loudly.
            die "GAP: untranslatable op inside an if/else arm"
              . " (arm did not reach the join) not yet lowered\n"
                if defined $join_addr
                && !(defined $end && ref $end && $$end == $join_addr);
            my $val = $arm_sim->stack_depth > $base_depth
                ? $arm_sim->pop_node
                : _undef_constant($factory);
            return ($val, $end, $arm_sim);
        };

        # op->next = false arm, op->other = true arm.
        my ($false_val, $false_end, $false_sim) = $walk_arm->($op->next);
        my ($true_val,  $true_end,  $true_sim)  = $walk_arm->($op->other);

        # Merge arm pad rebinds in EVERY context -- an assignment inside a
        # value-context arm (`my $y = $c ? ($x = 1) : 2`) is a binding side
        # effect that must become conditional exactly like the void form's.
        {
            my $base_scope  = $sim->scope_bindings;
            my $true_scope  = $true_sim->scope_bindings;
            my $false_scope = $false_sim->scope_bindings;
            my %targs = map { $_ => 1 } keys %$true_scope, keys %$false_scope;
            for my $targ (sort { $a <=> $b } keys %targs) {
                my $pre = $base_scope->{$targ};
                my $tv  = $true_scope->{$targ}  // $pre;
                my $fv  = $false_scope->{$targ} // $pre;
                next if !defined $tv && !defined $fv;
                next if defined $pre
                    && defined $tv && defined $fv
                    && $tv == $pre && $fv == $pre;
                $tv //= _undef_constant($factory);
                $fv //= _undef_constant($factory);
                $sim->define($targ, _make_ternary($factory, $cond, $tv, $fv));
            }
        }
        return $true_end // $false_end // $op->next
            if ($op->flags & 3) == 1;   # void: if/else statement, no value

        my $node = _make_ternary($factory, $cond, $true_val, $false_val);
        $sim->push_node($node);
        return $true_end // $false_end // $op->next;
    }

    # Walk a branch path until we hit a visited op, a function exit, or end.
    # $exits (optional) is the shared single-exit accumulator: an explicit
    # return/leavesub inside this arm is a control edge to the FUNCTION exit,
    # recorded there and terminating the arm with the 'exited' signal so the
    # caller's merge knows this arm does not rejoin (Phase 4b-1). When $exits
    # is not passed (older callers: dor/cond_expr/trycatch arms that compute a
    # value), a return falls through to the legacy stop-at-op behavior.
    sub _walk_branch ($cv, $op, $sim, $factory, $opmap, $visited, $exits = undef, $stop_at_exit = 0, $stop_addr = undef) {
        my $ctx = { mode => 'branch' };
        while ($$op) {
            # Convergence: reached the op where this arm rejoins the main path
            # (the branch op's op_next, passed by callers that know it). Checked
            # before the visited test so a caller can tell clean convergence
            # (returns the stop op) from a back-edge (returns a visited op
            # elsewhere -- a statement-modifier loop).
            return $op if defined $stop_addr && $$op == $stop_addr;
            # If we've already visited this op, we've converged
            return $op if $visited->{$$op};

            my $name = $op->name;
            my $is_leavesub = $name eq 'leavesub' || $name eq 'leavesublv';
            # With $stop_at_exit, the IMPLICIT trailing leavesub must NOT be
            # recorded as an exit -- it would consume the arm's computed value
            # (the value-returning && / || / ternary arm). Only an EXPLICIT
            # return is a real exit there. Without $stop_at_exit, both a return
            # and a leavesub terminate the arm as a function exit.
            my $exit_here = $exits
                && ($name eq 'return' || (!$stop_at_exit && $is_leavesub));
            if ($exit_here) {
                $visited->{$$op}++;
                push @$exits, _exit_record($sim, $factory,
                    $name eq 'return' ? 'return' : 'leavesub');
                return ($op, 'exited');
            }
            # $stop_at_exit (cond_expr / && / || value arms): stop BEFORE stepping
            # the implicit function exit (leavesub) so it does not consume the
            # arm's computed value. An EXPLICIT return in an arm is handled above
            # (recorded as an exit) so its pushmark/pop_to_mark stay balanced
            # (stopping before it would leak the mark and underflow the caller).
            if ($stop_at_exit
                && ($name eq 'leavesub' || $name eq 'leavesublv')) {
                return $op;
            }

            # `die` raises an exception -- a control exit this walker cannot
            # thread. Its OpMap entry is a generic mark-consumer (the special
            # Unwind handler lives in the main walk only), so stepping it
            # here would consume the args and walk on, silently ERASING the
            # exception from the program. Refuse loudly in value/modifier
            # arms; dor arms (no stop_at_exit) keep their existing behavior.
            if ($name eq 'die' && $stop_at_exit) {
                die "GAP: die inside a branch arm not yet lowered\n";
            }

            # A nested ternary / if-else inside an arm must be translated,
            # not treated as an unhandled stop -- otherwise the arm's value
            # degrades to the inner CONDITION and the inner assignments
            # vanish (the corpus D7/D9 miscompile).
            if ($name eq 'cond_expr' && $opmap->is_branch($name)
                && $sim->stack_depth > 0) {
                $visited->{$$op}++;
                $op = _handle_cond_expr($cv, $op, $sim, $factory, $opmap,
                    $visited);
                next;
            }

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

    # Key an element store/read by its container node and a constant index, so
    # a read after a store of the same element returns the stored value. Returns
    # undef when the index is not a constant (a dynamic index cannot be matched).
    sub _elem_key ($container, $index) {
        return undef unless $index->isa('SoN::IR::Node::Constant');
        return $container->id . ':' . ($index->value // '');
    }

    # The implicit @_ argument array. Bare shift/pop operate on it, and a
    # list-assignment `my (...) = @_` destructures it. @_ is the package array
    # *main::_, so it is modeled as a StashAccess (a real array source), never a
    # string Constant.
    sub _args_source ($factory) {
        return $factory->make('StashAccess',
            stash_name => 'main',
            var_name   => '_');
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

    # Resolve the GV of a gv/gvsv op. Unthreaded perls store it on the op
    # (B::SVOP, ->sv is a B::GV); threaded perls store it in the pad
    # (B::PADOP at ->padix, or an SVOP with a B::SPECIAL sv and ->targ).
    sub _op_gv ($cv, $op) {
        if ($op->can('sv')) {
            my $sv = $op->sv;
            return $sv if $$sv && $sv->isa('B::GV');
        }
        my $ix = $op->can('padix') ? $op->padix : $op->targ;
        if ($ix) {
            my $padl = $cv->PADLIST;
            if ($$padl) {
                my $gv = $padl->ARRAYelt(1)->ARRAYelt($ix);
                return $gv if $$gv && $gv->isa('B::GV');
            }
        }
        return undef;
    }

    # Get the variable name for a pad index.
    #
    # When a usable pad name is unavailable (anonymous/temporary slots), the
    # fallback name is suffixed with the targ. PadAccess identity is keyed on
    # varname (not targ -- see PadAccess::content_hash), so the suffix keeps
    # distinct unnamed slots distinct rather than collapsing them all to '$?'.
    sub _padname ($cv, $targ) {
        my $padlist = $cv->PADLIST;
        return "\$?$targ" unless $$padlist;
        my $padnames = $padlist->ARRAYelt(0);
        my $pn = $padnames->ARRAYelt($targ);
        return "\$?$targ" unless ref $pn eq 'B::PADNAME';
        my $name = eval { $pn->PV };
        return defined $name ? $name : "\$?$targ";
    }

    # Convert a PMOP pmflags bitmask to a flag string (e.g. "gi")
    sub _pmflags_to_str ($flags) {
        my $str = '';
        $str .= 'm' if $flags & 1;        # PMf_MULTILINE
        $str .= 's' if $flags & 2;        # PMf_SINGLELINE
        $str .= 'i' if $flags & 4;        # PMf_FOLD (case-insensitive)
        $str .= 'x' if $flags & 8;        # PMf_EXTENDED
        $str .= 'g' if $flags & 8388608;  # PMf_GLOBAL
        $str .= 'r' if $flags & PMf_NONDESTRUCT; # s///r
        return $str;
    }
}

1;
