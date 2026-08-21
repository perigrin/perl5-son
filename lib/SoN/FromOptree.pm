# ABOUTME: Translates perl5 compiled optrees into SoN IR graphs.
# ABOUTME: Uses stack simulation to reconstruct data flow from the op_next chain.

use v5.42.0;
use utf8;
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

    # Subst PMOP pmflags bits. /r (non-destructive) returns a new string and
    # leaves the source untouched, so it must not rebind the pad. /e (eval)
    # makes the replacement a code subtree rather than a literal string --
    # out of the runtime-free regex scope, so it is a loud GAP.
    use constant PMf_NONDESTRUCT => 0x4000000;   # 67108864
    use constant PMf_EVAL        => 0x2000000;   # 33554432 (s///e)

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
        Concat    => 'Str',
        Length    => 'Int',
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

    # _coerce_to_str($factory, $node) -- return a node whose stamp is Str,
    # wrapping $node in a Coerce(X -> Str) unless it is already Str.
    #
    # This is THE X->Str injection point: interpolation ("ok $n" is coercion,
    # not interpolation), Print's arguments, and StrEq/StrNe's operands all
    # route through it, so those operators never learn a representation.
    #
    # It builds a Coerce, not a Stringify: `Stringify(X)` IS `Coerce(X -> Str)`,
    # and the two were separate node types implementing one edge -- which had
    # already diverged in the backend (Coerce's Bool arm recorded no string
    # length, Stringify's did). One node type, one conversion.
    #
    # A node already stamped Str (a Str Constant segment, a nested Concat)
    # passes through unchanged.
    #
    # An UNSTAMPED operand gets from_repr 'Unknown' -- the PESSIMISTIC top type,
    # TypeScript's `unknown` rather than its `any`. At this point in the
    # pipeline the type genuinely IS undetermined: a direct call's result, for
    # instance, cannot be typed here because the callee's graph may not be
    # translated yet. Saying "Unknown" states that honestly, and obliges a later
    # pass to NARROW it before anything is lowered.
    #
    # This used to write 'Scalar', with the rationale that "the backend resolves
    # the source representation from the operand itself". The backend does not:
    # it dispatches on from_repr and GAPs. So the producer wrote a placeholder
    # meaning "ignore this" and the backend read it as a claim -- and because
    # Scalar is a REAL type, its GAP could not distinguish "this scalar type is
    # not lowered yet" from "nothing ever typed this". Measured cost:
    # perl5/t/cmd/elsif.t, whose four `main::foo` calls ARE typed Int once the
    # loader resolves them, failed as `Coerce[Scalar->Str] is not lowered`.
    sub _coerce_to_str ($factory, $node) {
        my $stamp = $node->stamp;
        return $node if defined $stamp && $stamp->type eq 'Str';
        return $factory->make('Coerce',
            from_repr => (defined $stamp ? $stamp->type : 'Unknown'),
            to_repr   => 'Str',
            inputs    => [$node],
            stamp     => SoN::IR::Stamp->new(type => 'Str'));
    }

    # _coerce_int_to_num($factory, $node) -- return a node whose stamp is Num,
    # wrapping an Int-stamped $node in a Coerce(Int->Num) unless it is already
    # non-Int. Perl `/` is always floating-point division, so an Int operand of a
    # Divide is numerically coerced to a Num first. The Coerce node is stamped Num
    # so the wire stamp -> %STAMP_TO_REPR arrives representation=Num on the chalk
    # side, satisfying TypedInvariant's `Divide => Num` requirement and letting
    # _lower_coerce emit the sitofp exactly once (a second sitofp on an already-
    # double ref would be invalid LLVM). Only an Int operand is wrapped; a Num (or
    # unstamped) operand passes through unchanged -- Coerce's result is
    # unconditionally Num, so this is the division coercion contract, not a guess.
    sub _coerce_int_to_num ($factory, $node) {
        my $stamp = $node->stamp;
        return $node unless defined $stamp && $stamp->type eq 'Int';
        return $factory->make('Coerce',
            from_repr => 'Int',
            to_repr   => 'Num',
            inputs    => [$node],
            stamp     => SoN::IR::Stamp->new(type => 'Num'));
    }

    # _array_element_stamp($array) -> the element stamp of an ArrayRef node
    # (the join of its element stamps), or undef when the array is not a literal
    # ArrayRef or any element is unstamped. Used to stamp shift/pop's removed
    # value. An empty array has no element type, so returns undef (unstamped).
    sub _array_element_stamp ($array) {
        return undef unless defined $array
            && $array->operation eq 'ArrayRef';
        my @stamps = map { $_->stamp } $array->inputs->@*;
        return undef if !@stamps || grep { !defined } @stamps;
        my $acc = shift @stamps;
        $acc = SoN::IR::Stamp::join($acc, $_) for @stamps;
        return $acc;
    }

    # _is_aggregate_node($node) -- true iff the node is an array/hash aggregate
    # a Length can count: an ArrayRef/HashRef constructor, or a node bound to an
    # aggregate (its stamp is ArrayRef/HashRef). A scalar (e.g. a Str Constant
    # left by a symbolic `@$str` deref) is NOT an aggregate.
    sub _is_aggregate_node ($node) {
        return false unless defined $node;
        my $op = $node->operation;
        return true if $op eq 'ArrayRef' || $op eq 'HashRef';
        my $stamp = $node->stamp;
        return false unless defined $stamp;
        my $t = $stamp->type;
        return ($t eq 'ArrayRef' || $t eq 'HashRef') ? true : false;
    }

    # _rhs_is_aggregate_access($assign_op) -- true iff the RHS of a scalar
    # assignment (padsv_store / sassign) is a genuine aggregate-VARIABLE read
    # (padav/padhv/rv2av/rv2hv), i.e. an array/hash in scalar context that must
    # yield its count. Distinguishes `my $n = @a` (padav, count) from
    # `my $r = [1,2,3]` (anonlist -- a scalar REFERENCE literal, NOT a count):
    # both build an identical ArrayRef node, so the node's repr cannot tell them
    # apart -- only the source op can. Mirrors the `scalar @a` handler's op-name
    # predicate. $op->first is the RHS value op for both padsv_store and sassign.
    sub _rhs_is_aggregate_access ($op) {
        return false unless $op->can('first');
        my $rhs = $op->first;
        return false unless $rhs && $$rhs;
        return $rhs->name =~ /^(padav|padhv|rv2av|rv2hv)$/ ? true : false;
    }

    # Translate a code reference to a SoN graph
    sub translate ($class_or_self, $coderef) {
        my $cv = B::svref_2object($coderef);
        die "Not a CODE ref" unless $cv->isa('B::CV');
        return _translate_from($cv, $cv->START);
    }

    # Translate the top-level program (main_root/main_start/main_cv) to a SoN
    # graph -- the ENTRY half of the bare-file protocol. A bare file's
    # top-level statements are not a CV: B::main_cv is a real B::CV (it HAS a
    # padlist, so pad access works) but its own ->START is 'gv', not the
    # program's actual entry -- so we must walk from B::main_start, not from
    # $cv->START as translate() does. B::main_root (a 'leave' LISTOP, never
    # 'leavesub') is passed through as program_root so the walk can recognize
    # THAT SPECIFIC leave as the program's exit, without matching every
    # ordinary block-ending leave (see _translate_from's exit check).
    sub translate_root ($class_or_self) {
        my $cv = B::main_cv;
        die "GAP: no top-level program (main_root is empty)\n"
            unless $$cv && ${ B::main_root() };
        return _translate_from($cv, B::main_start(),
            program_root => ${ B::main_root() });
    }

    # _translate_from($cv, $start_op, program_root => $addr?) -- shared walk
    # driving both translate() (a CV, $start_op == $cv->START) and
    # translate_root() (the top-level program, $start_op == B::main_start(),
    # $cv == B::main_cv). $program_root, when given, is the address of the
    # bare-program's root 'leave' op -- the ONLY 'leave' the exit check below
    # is allowed to treat as a function exit (see the leavesub/leave check).
    sub _translate_from ($cv, $start_op, %opts) {
        my $program_root = $opts{program_root};

        my $factory = SoN::IR::NodeFactory->new();
        my $opmap   = SoN::FromOptree::OpMap->new();
        my $start   = $factory->make_cfg('Start');
        my $mem     = $factory->make('MemStart');
        my $sim     = SoN::FromOptree::StackSim->new(
            control => $start, memory => $mem);

        my %visited;
        my $op = $start_op;
        # @exits accumulates every explicit return/leavesub exit as
        # { control => <cfg node>, value => <value node> }. A return inside a
        # branch arm is a control edge to the FUNCTION exit, not a value that
        # merges back into the post-branch stack -- so we collect all exits and
        # build ONE Region+Phi+Return at the end (single-exit normalization,
        # Phase 4b-1). Shared with _walk_branch via $ctx so an early return in
        # an arm records its exit instead of dying / truncating the graph.
        my @exits;
        my $main_terminated = 0;   # set when the main path hits return/leavesub
        # $ctx->{pending_method}: method name recorded by method_named for the
        # following entersub (method dispatch). Carried on $ctx so the SHARED
        # entersub/method_named handlers work identically in the main walk and in
        # _walk_branch/_step (a void method call in a branch arm -- zhi 019f2df7).
        # is_program: this walk is the top-level program, not a sub -- only
        # translate_root passes program_root.
        #
        # Currently UNUSED, and kept deliberately. A package-scalar definition
        # made inside a sub ESCAPES it: `our $g = 5; sub bump { $g = 9 }
        # bump(); print $g` is 9 in perl and 5 here, because a binding is
        # per-graph and each sub is translated as its own graph before any
        # inlining. This is the discriminator the fence for that needs.
        #
        # It cannot be switched on yet: the chalk corpus harness wraps every
        # case in `sub corpus_case { ... }`, so a fragment is indistinguishable
        # from a real sub and all 12 package-scalar cases GAP (measured). See
        # the followups, Part H.
        my $ctx = { mode => 'main', exits => \@exits,
                    is_program => (defined $program_root ? 1 : 0) };

        while ($$op) {
            last if $visited{$$op}++;

            my $name = $op->name;

            # dor op: $lhs // $rhs
            if ($opmap->is_branch($name) && $name eq 'dor') {
                my $lhs = $sim->pop_node;
                # Walk the fallback arm (RHS of //). Pass @exits + stop_at_exit
                # so an EXPLICIT return/die-exit in the fallback (`E // return X`,
                # the ubiquitous lib/ guard idiom) is recorded as a real function
                # exit, not silently consumed as the fallback value. The arm
                # converges at this op's op_next.
                my $stop_addr = ${ $op->next };
                my $rhs_sim = $sim->snapshot;
                my ($rhs_end, $rhs_sig)
                    = _walk_branch($cv, $op->other, $rhs_sim, $factory, $opmap,
                        \%visited, \@exits, 1, $stop_addr);

                if (($rhs_sig // '') eq 'exited') {
                    # `E // return X`: the fallback LEAVES the function when E is
                    # undefined. Model it as a guarded exit -- exactly the shape
                    # `return X if C` builds. The EXIT arm must be the If's TRUE
                    # branch so it aligns with the exit's value in the single-exit
                    # Phi (the backend wires Phi arm 0 = then/true, arm 1 =
                    # else/false, and _build_single_exit records the exit value
                    # FIRST). So the guard tests NOT-defined(E) -- true when E is
                    # undef (the exit path) -- and the main path continues on the
                    # FALSE Proj (index 1), where E IS defined and the dor value is
                    # E (`$x = E`). Without this the return vanished and E //
                    # return became DefinedOr(E, E).
                    my $defined = $factory->make('Defined', inputs => [$lhs]);
                    my $undef   = $factory->make('Not', inputs => [$defined]);
                    my $if_node = $factory->make_cfg('If',
                        inputs => [$sim->control, $undef]);
                    my $cont_proj = $factory->make_cfg('Proj',
                        inputs => [$if_node], index => 1);   # defined -> continue
                    $sim->set_control($cont_proj);
                    $sim->push_node($lhs);                   # dor value is E
                    $op = $op->next;
                    next;
                }

                # Value fallback (`E // V`): a single DefinedOr the backend
                # expands to the short-circuit br+phi at lowering.
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

                # Memory-SSA 2b: a void branch whose arm STORES to an element
                # (`if ($c) { $a[0] = 9 }`) must build real control flow so the
                # store is CONTROL-DEPENDENT on the branch (emitted only when the
                # guard is taken) and a memory-Phi merges the arms. Build the If +
                # Proj(true) BEFORE the arm walk and set the arm control to
                # Proj(true), so the store (control = $sim->control at build time)
                # lands on the true arm. The base continues on Proj(false); the
                # post-walk merge() builds the Region + memory-Phi. Gated on an
                # element-store arm so the working scalar/value/exit paths are
                # untouched.
                # An arm that TERMINATES (`die`, `exit`) needs real control flow
                # for the same reason a void-call arm does: the effect must be
                # control-dependent on the guard. It was not listed here, and an
                # arm whose ONLY content is a terminator is neither an element
                # store nor a void call -- so no If was built, the terminator
                # was left off the control chain, and the statement after the
                # branch ran unconditionally. Measured on
                # `my $c=1; say 1; if ($c) { exit 4 } say 2;`:
                #   perl  "1\n" exit 4      chalk  "1\n2\n" exit 0
                # Wrong stdout AND wrong status, silently. `die` in the same
                # shape had the identical defect; an if/ELSE with a die arm
                # already worked (corpus T2), which is what made it look covered.
                my $mem_branch =
                    ($op->flags & 3) == 1   # OPf_WANT_VOID
                    && (_arm_has_element_store($op->other, $stop_addr)
                        || _arm_has_void_call($op->other, $stop_addr)
                        || _arm_has_die($op->other, $stop_addr));
                my ($if_node, $true_proj, $false_proj);
                if ($mem_branch) {
                    $if_node   = $factory->make_cfg('If',
                        inputs => [$sim->control, $lhs]);
                    # `and` (if C): true arm runs the body. `or` (unless C): the
                    # body runs on the FALSE arm.
                    my ($body_idx, $cont_idx) =
                        $name eq 'and' ? (0, 1) : (1, 0);
                    $true_proj  = $factory->make_cfg('Proj',
                        inputs => [$if_node], index => $body_idx);
                    $false_proj = $factory->make_cfg('Proj',
                        inputs => [$if_node], index => $cont_idx);
                    $rhs_sim->set_control($true_proj);
                    $sim->set_control($false_proj);
                }

                my %pre_arm_visited = %visited;
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
                    # The EXIT must land on the If's TRUE branch (index 0) so it
                    # aligns with the exit value in the single-exit Phi -- the
                    # backend wires Phi arm 0 = then/true, arm 1 = else/false,
                    # and _build_single_exit records the exit value FIRST (arm 0).
                    #
                    #  and (`return X if C`):     exit when C true. C already IS
                    #    the exit condition -> If(C), continue on the FALSE Proj
                    #    (index 1) where C is false and the guard is not taken.
                    #  or  (`return X unless C`): exit when C FALSE. The exit
                    #    condition is Not(C) -> If(Not(C)) so the exit is again the
                    #    TRUE branch, continue on the FALSE Proj (index 1) where C
                    #    is true and the guard is not taken. Without the negation
                    #    the exit value (Phi arm 0) landed on the true branch while
                    #    the exit actually fired on the false branch -- an inverted
                    #    polarity that miscompiled (return-X-unless returned the
                    #    fall-through when C was false).
                    my $cond = $name eq 'and'
                        ? $lhs
                        : $factory->make('Not', inputs => [$lhs]);
                    my $if_node = $factory->make_cfg('If',
                        inputs => [$sim->control, $cond]);
                    my $cont_proj = $factory->make_cfg('Proj',
                        inputs => [$if_node], index => 1);   # guard not taken
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
                    # A genuine `EXPR while COND` back-edge re-enters the
                    # CONDITION HEAD -- an op that was already visited BEFORE this
                    # arm walk began (the outer walk stepped through the condition
                    # to reach this `and`). A NESTED branch inside the arm
                    # (if($c){if($d){...}}) instead makes $rhs_end the inner
                    # branch's forward join -- an op first visited DURING the arm
                    # walk. Descending into _translate_while_loop for that forward
                    # join walks with a broken memory state and crashes (a
                    # Subscript with an undef memory input). Require $rhs_end to be
                    # a TRUE back-edge (visited before the arm) so a nested-branch
                    # join falls through to the convergence check below and GAPs
                    # loudly instead. (Raw op-address ordering is NOT a reliable
                    # backward-edge signal -- allocation order != execution order;
                    # pre-arm visitation is.)
                    if (!$mem_branch
                            && $name eq 'and'
                            && defined $rhs_end && ref $rhs_end
                            && $$rhs_end != $stop_addr
                            && $pre_arm_visited{$$rhs_end}) {
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
                    # Memory-SSA 2b: an element-store arm was walked on Proj(true)
                    # with a control-dependent store. merge() builds the Region
                    # (over false_proj + the arm's control) and the memory-Phi,
                    # plus Phis for any scope vars the arm rebound. The read after
                    # the branch takes the merged memory / bindings.
                    if ($mem_branch) {
                        # A void-call arm that ALSO rebinds a scope var USED to
                        # GAP here: merge() builds a value-Phi for the rebound
                        # slot, and the backend could not place it because the
                        # arm's control chain ends on the CALL rather than on
                        # the Proj (Phi-before-Region).
                        #
                        # Both halves of that are fixed. chalk `f2971b5f` places
                        # a Phi read before its Region, and `9ce43cdd` walks a
                        # Region input's control chain back to its Proj -- which
                        # is exactly this shape, since a void call is what ends
                        # the chain somewhere other than the Proj.
                        #
                        # Re-measured 2026-08-20 across 14 bilateral shapes: the
                        # block form, the statement-modifier spelling, two
                        # rebinds in one arm, if/else where BOTH arms call and
                        # rebind, a rebind that READS the slot after the call,
                        # and a string rebind. All 14 match perl on stdout and
                        # exit status. See the chalk repo,
                        # docs/plans/2026-08-20-2b3-measured-defect-3-is-closed.md
                        #
                        # THE DETECTION IS NOT DISABLED, which is what the
                        # bilateral guard in t/from-optree-arm-scan-bound.t
                        # exists to prevent. The arm shape that genuinely cannot
                        # lower -- a scalar rebind AND an element store in one
                        # arm -- still refuses, in the backend where the
                        # unlowerable step actually is
                        # (Target/LLVM/Context.pm: "a branch arm that both
                        # rebinds a scalar and stores an element"). Verified
                        # firing today on
                        # `if (...) { print "x\n"; $a[0] = 9; $n = 5 }`.
                        # The element-store sassign pushes its stored VALUE (perl
                        # assignment returns its value); in void context that
                        # value is discarded. Drop the arm's leftover stack down
                        # to the base depth so merge() does not build a spurious
                        # (and ill-typed) stack Phi over a dead value.
                        $rhs_sim->pop_node
                            while $rhs_sim->stack_depth > $sim->stack_depth;
                        $sim->merge($rhs_sim, $factory, $if_node);
                        $op = $op->next;
                        next;
                    }

                    my $base_scope = $sim->scope_bindings;
                    my $arm_scope  = $rhs_sim->scope_bindings;
                    for my $targ (sort _scope_key_order keys %$arm_scope) {
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

            # A runtime range (range/flip/flop) PRODUCES a list -- it is not a
            # control branch. A constant range (1..4) constant-folds to a const[AV]
            # and never reaches here; only a NON-constant bound (1..$n) emits these
            # ops. They have no handler, so the generic branch-skip below dropped
            # the range's list value and the aassign saw a 1-element stack (`my
            # @q=(1..$n); scalar @q` gave 1, oracle 4 -- a silent miscompile, zhi
            # 019f5b4b). Lowering a runtime range (a counted N-element expansion) is
            # a feature not yet built; GAP loudly rather than skip.
            if ($name eq 'range' || $name eq 'flip' || $name eq 'flop') {
                die "GAP: a runtime range with a non-constant bound (1..\$n) is not"
                  . " yet lowered\n";
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
                # A bare block (`{ ... }`), `package Foo { ... }`, and `class
                # Foo { ... }` ALSO compile to enterloop -- but with no back
                # edge: nextop and lastop both point at the same leaveloop. A
                # real while/until/C-style for has nextop = unstack (a
                # distinct op from lastop). Keying on this (not on redoop -- a
                # bare block DOES have redoop set) tells the two apart; only a
                # genuine back edge goes through _translate_while_loop.
                # Precedent: _is_postfix_while discriminates the analogous
                # enter/leave shape the same way.
                my $nx = $op->can('nextop') ? $op->nextop : undef;
                my $ls = $op->can('lastop') ? $op->lastop : undef;
                if (ref $nx && $$nx && ref $ls && $$ls && $$nx == $$ls) {
                    $op = $op->next;
                    next;
                }
                _translate_while_loop($cv, $op->next, $sim, $factory, $opmap, \%visited);
                # Continue after the loop; the B::LOOP op's lastop is leaveloop.
                $op = $op->can('lastop') ? $op->lastop : $op->next;
                next;
            }

            # postfix-while (`EXPR while COND`) compiles to enter/leave (NOT
            # enterloop) with a back-edge: the and/or's body arm ends in an
            # `unstack` that jumps back to the condition head (enter->next). Detect
            # it HERE, at `enter`, and translate the whole loop via the two-phase
            # scout BEFORE the main walk builds any real condition/body node --
            # otherwise the pre-walk commits pre-loop-constant orphans that
            # _translate_while_loop's Phi-based re-walk leaves dead in the graph
            # (zhi 019f29ed). The condition head is enter->next; skip to `leave`.
            if ($name eq 'enter') {
                my $cond_head = $op->next;
                if (_is_postfix_while($op)) {
                    _translate_while_loop($cv, $cond_head, $sim, $factory,
                        $opmap, \%visited);
                    # Advance past the loop body to `leave`, then continue.
                    my %skip;
                    while ($$op && $op->name ne 'leave' && !$skip{$$op}++) {
                        $op = $op->next;
                    }
                    $op = $op->next if $$op;   # step past leave
                    next;
                }
                # Not a postfix-while: `enter` is a no-op scope marker, skip it.
                $op = $op->next;
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
                # Three shapes reach an OPf_STACKED enteriter:
                #   CONST RANGE   `for my $i (2..5)`: two integer-Constant bounds.
                #   RUNTIME RANGE `for my $i (0..$n)` / `(0..$#a)`: two scalar-Int
                #                 bounds where at least one is a runtime value
                #                 (PadAccess/Length) -- the #1 lib/ blocker.
                #   ARRAY         `for my $x (@a)`: a single aggregate.
                # for/foreach are aliases (same optree).
                my $two_scalar_int = $bounds->@* == 2
                    && !(grep { _is_aggregate_node($_) } $bounds->@*);
                if ($two_scalar_int) {
                    # A runtime LOW bound (`for my $i ($lo..$hi)`) is not yet
                    # lowered: the induction Phi init would be a runtime value
                    # whose stamp is not propagated through the back-edge (the
                    # loop-carried-stamp fixpoint), and the range's flip/flop
                    # materialization crashes the body walk. A constant low with a
                    # runtime high (`0..$n`, `0..$#a`) IS handled. GAP cleanly
                    # here rather than crashing downstream.
                    die "GAP: foreach over a range with a runtime LOW bound "
                      . "(for my \$i (\$lo..\$hi)) not yet lowered\n"
                        unless $bounds->[0]->isa('SoN::IR::Node::Constant')
                            && ($bounds->[0]->const_type // '') eq 'integer';
                    _translate_foreach_range($cv, $op, $sim, $factory, $opmap,
                        \%visited, $bounds->@*);
                }
                elsif ($bounds->@* == 1 && _is_aggregate_node($bounds->[0])) {
                    _translate_foreach_array($cv, $op, $sim, $factory, $opmap,
                        \%visited, $bounds->[0]);
                }
                elsif ($bounds->@* == 1
                        && $bounds->[0]->operation eq 'FieldAccess') {
                    # `for my $x ($items->@*)` over an aggregate FIELD: the
                    # rv2av-deref left the FieldAccess ref on the stack. The
                    # field's ArrayRef type + element type are inferred on the
                    # Chalk loader side (from the aggregate default), so iterate it
                    # like a runtime array (Length(field) + Subscript(field,i)).
                    # A `@$r` over an @_-sourced ref (a Subscript bound) stays a
                    # GAP -- its element type is statically unknowable. zhi 019f61ad.
                    _translate_foreach_array($cv, $op, $sim, $factory, $opmap,
                        \%visited, $bounds->[0]);
                }
                else {
                    die "GAP: foreach with unrecognized bounds shape not yet lowered\n";
                }
                # Continue after the loop; the B::LOOP op's lastop is leaveloop.
                $op = $op->can('lastop') ? $op->lastop : $op->next;
                next;
            }

            # leaveloop - end of loop, continue
            if ($name eq 'leaveloop') {
                $op = $op->next;
                next;
            }

            # Handle entersub / method_named via the shared handlers so a
            # (void) method call translates identically here and inside a branch
            # arm (_walk_branch/_step). Method dispatch is signalled by a
            # preceding method_named recorded on $ctx->{pending_method}.
            if ($name eq 'entersub') {
                _handle_entersub($cv, $op, $sim, $factory, $ctx);
                $op = $op->next;
                next;
            }
            if ($name eq 'method_named') {
                _handle_method_named($cv, $op, $ctx);
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
            # A bare program's root is a plain 'leave' (never 'leavesub') --
            # but 'leave' ALSO ends ordinary blocks (if/while/do bodies), so
            # only the program's OWN root op qualifies as a function exit.
            # $program_root is undef for every ordinary CV walk (translate()),
            # so this arm is unreachable there; a random mid-body 'leave' at
            # translate_root() time still falls through to the "unknown op"
            # handler below (skip + walk past), the existing behavior for a
            # 'leave' that is not this exit check's business.
            my $is_program_exit = defined $program_root && $$op == $program_root;
            if ($name eq 'leavesub' || $name eq 'leavesublv' || $is_program_exit) {
                push @exits, _exit_record($sim, $factory, 'leavesub', $op,
                                         $is_program_exit);
                $main_terminated = 1;
                last;
            }

            # Handle subst - regex substitution op: s/pattern/replacement/flags
            if ($name eq 'subst' && $op->isa('B::PMOP')) {
                my $pattern = $op->precomp // '';
                my $flags   = _pmflags_to_str($op->pmflags);
                # s///e: the replacement is a code subtree, not a literal
                # string. Emitting a RegexSubst with a guessed replacement
                # would silently miscompile (the RC4 class), so refuse loudly.
                die "GAP: s///e (code replacement) not yet lowered\n"
                    if $op->pmflags & PMf_EVAL;
                # An interpolated (multi-part) replacement -- `s/a/$y$z/`,
                # `s/a/x$y/` -- is a runtime substcont subtree (pmreplroot set),
                # NOT a single folded const. The handler below pops ONE stack
                # Constant and uses it as the whole replacement, silently
                # dropping every other part. A single interpolated variable
                # (`s/a/$y/`) folds to a compile-time Constant under
                # rpeep-suppression (pmreplroot NULL) and stays correct; only a
                # genuine subtree GAPs. Refuse loudly until it is lowered.
                my $replroot = $op->pmreplroot;
                die "GAP: s/// interpolated (multi-part) replacement not yet lowered\n"
                    if $replroot && ref($replroot) && $$replroot;
                my $nondestruct = $op->pmflags & PMf_NONDESTRUCT;
                # In scalar/boolean context a DESTRUCTIVE s/// returns the
                # integer match COUNT, not the rewritten string (only /r
                # yields a string). The handler stamps every result Str and
                # pushes the rewritten string -- correct for void context and
                # for /r, a silent value+type miscompile for scalar-context
                # destructive subst. GAP loudly until count-context is lowered.
                die "GAP: s/// count-context result (scalar-context destructive) not yet lowered\n"
                    if !$nondestruct && ($op->flags & 3) != 1;   # OPf_WANT != VOID
                # The target is keyed on the pad targ. targ 0 means an implicit
                # $_ or a package/global target (the GV is on the stack, not a
                # pad slot) -- the handler cannot name it, so it used to
                # fabricate a slot-0 rebind and silently drop the substitution.
                # GAP loudly until non-pad targets are lowered.
                my $targ    = $op->targ;
                die "GAP: s/// on an implicit \$_ or package/global target not yet lowered\n"
                    unless $targ;
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
                # rebind -- only push the result value ($nondestruct above).
                $sim->define($targ, $node) unless $nondestruct;
                $sim->push_node($node);
                $op = $op->next;
                next;
            }

            # Handle die specially: creates an Unwind CFG node, nothing pushed to stack
            if ($name eq 'die') {
                my $args = $sim->pop_to_mark;
                my $unwind = $factory->make_cfg('Unwind',
                    inputs => [$args]);
                $unwind->set_control_in($sim->control);
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
        # $program_root marks a top-level walk: the same no-return-value rule
        # applies to a fall-off-the-end exit as to the explicit one above.
        my $is_program = defined $program_root ? 1 : 0;
        if (!$main_terminated && $sim->stack_depth > 0) {
            push @exits, _exit_record($sim, $factory, 'fallthrough', undef,
                                      $is_program);
        }
        elsif (!@exits) {
            # No explicit return anywhere and an empty stack: undef return.
            push @exits, _exit_record($sim, $factory, 'fallthrough', undef,
                                      $is_program);
        }

        my $ret = _build_single_exit($factory, \@exits);
        return _graph_of_reachable($start, $ret);
    }

    # _exit_record($sim, $factory, $kind) -> { control, value }
    # Capture a function-exit edge: the control node at this point and the
    # value being returned. 'return' pops to the mark (the return-list's last
    # value); 'leavesub'/'fallthrough' take the top of stack; an empty stack
    # is an undef return.
    # A `return ($a, $b, ...)` / trailing `($a, $b, ...)` yields a LIST. In
    # scalar/comma context the value is the last element; in list context the
    # caller receives every element. The sub body is compiled once and is
    # context-independent, so the producer cannot know the caller's runtime
    # wantarray -- a >1-value return cannot be soundly collapsed to a single
    # scalar Return, and keeping only the last value silently drops the rest for
    # a list-context caller (`my @x = f()` would see 1 element, not N). The
    # multi-value shape is an OP_LIST with a pushmark and >1 value child. Detect
    # it structurally (NOT via stack depth, which cross-path branch residue
    # inflates) so a single-value guarded return is not over-GAPped. zhi 019f5e41.
    sub _leavesub_returns_list ($leave_op) {
        return false unless $leave_op && ref($leave_op) && $$leave_op;
        my $lineseq = $leave_op->first;
        return false unless $lineseq && $$lineseq && $lineseq->name eq 'lineseq';
        # The last kid of the lineseq is the sub's trailing (result) statement.
        my ($last, $kid) = (undef, $lineseq->first);
        while ($kid && $$kid) { $last = $kid; $kid = $kid->sibling; }
        # An implicit trailing list is an OP_LIST; an explicit `return (LIST)`
        # is an OP_RETURN wrapping the same pushmark+values (the return op is
        # peephole-elided from the EXEC chain, so this leavesub branch handles
        # both). Either way the >1-value shape is the same GAP.
        return false
            unless $last && ($last->name eq 'list' || $last->name eq 'return');
        # Count value-producing children (skip the leading pushmark). >1 => list.
        my $n = 0;
        my $c = $last->first;
        while ($c && $$c) {
            $n++ if $c->name ne 'pushmark';
            $c = $c->sibling;
        }
        return $n > 1 ? true : false;
    }

    sub _exit_record ($sim, $factory, $kind, $exit_op = undef, $is_program = 0) {
        my $value;
        # A PROGRAM has no return value. Its top level runs every statement in
        # VOID context -- perl compiles the trailing statement that way
        # (`padsv ... v`, `leave ... vKP`), and the last value has no effect on
        # exit status (`perl -e 'my $x = 5; $x'` exits 0, as does a trailing 0).
        # A program's observable contract is stdout plus exit status; the status
        # comes from `die` or `exit`, never from a value.
        #
        # So anything still on the simulated stack here is RESIDUE from an
        # earlier statement that was never consumed, and taking it makes the
        # Return adopt an unrelated value. Measured before this guard:
        #   my @a = (1,2,3); say(scalar @a)             Return <- ArrayRef
        #   my $n=5; my $x=0; $x = 1 if $n>0; say($x)   Return <- Constant(0),
        #                                               with TWO values left
        # Drop the residue and fall through to the Undef below.
        if ($is_program) {
            $sim->pop_node while $sim->stack_depth > 0;
        }
        elsif ($kind eq 'return') {
            my $args = $sim->pop_to_mark;
            die "GAP: multi-value list return (return LIST) not yet lowered\n"
                if $args->@* > 1;
            $value = $args->@* ? $args->[-1] : undef;
        }
        elsif ($sim->stack_depth > 0) {
            # The peephole optimizer elides an explicit `return` when it is the
            # trailing statement: `sub { (10,20,30) }` compiles to const pushes
            # then leavesub (no return op, no runtime pushmark). Recover the
            # multi-value shape from the leavesub's optree, not the stack.
            die "GAP: multi-value list return (trailing list) not yet lowered\n"
                if _leavesub_returns_list($exit_op);
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
            my ($ctrl, $value) = $exits->[0]->@{qw(control value)};
            # Produce-time control: control is carried on control_in, never
            # flattened into inputs. This subsumes the old ctrl-is-a-stmt-
            # effect-Call special case (previously a VOID stmt-effect Call as
            # the trailing control could not lead inputs without being
            # misread as the return VALUE, so it was put second instead) --
            # control_in is never a data input, so a Return's inputs is
            # always exactly [value] regardless of what kind of node control
            # is.
            my $ret = $factory->make_cfg('Return', inputs => [$value]);
            $ret->set_control_in($ctrl) if defined $ctrl;
            return $ret;
        }
        my $region = $factory->make_cfg('Region',
            inputs => [map { $_->{control} } @$exits]);
        # This Region merges independent function exits, not a single If/
        # Loop's two arms -- there is no single caller-supplied owner the
        # way the mem_branch/cond_expr/mid-body-break merge() sites have.
        # But the common shape (`return X if C`, `E // return X`) IS an
        # early exit guarded by exactly one If: one exit's control chains
        # (via control_in) to a Proj of that If. Scan every exit's control
        # for such a chain and adopt the first If/Loop found as the owner,
        # so the backend's control-chain walk can still reach it -- the
        # same best-effort scan the loader used to do at load time.
        # Resolve each exit's control back to the Proj its arm hangs off. This
        # walk used to be written inline here -- the FOURTH copy of the same
        # search -- and is now the one in StackSim, which merge() also uses.
        my @exit_projs = map { SoN::FromOptree::StackSim::arm_proj($_->{control}) }
                             @$exits;

        my $owner;
        EXIT: for my $arm (@exit_projs) {
            next unless defined $arm;
            my $cand = $arm->inputs->[0];
            if (defined $cand && blessed($cand)) { $owner = $cand; last EXIT }
        }
        $owner->set_region($region) if defined $owner && $owner->can('set_region');

        # The walk above already knows which Proj each exit came from, so
        # RECORD it: inputs[i] pairs with predecessors[i] and the consumer reads
        # arm identity instead of searching for it again. Supplied only when
        # EVERY exit resolved -- the consumer pairs by position, so a partial
        # list would silently mis-pair.
        my @preds = (grep { defined } @exit_projs) == @exit_projs
            ? @exit_projs : ();

        my $phi = $factory->make('Phi',
            inputs => [map { $_->{value} } @$exits],
            region => $region,
            (@preds ? (predecessors => [@preds]) : ()));
        my $ret = $factory->make_cfg('Return', inputs => [$phi]);
        $ret->set_control_in($region);
        return $ret;
    }

    # SoN::IR::Graph->nodes() returns only nodes reachable from the
    # graph's own %cache (inputs unconditionally, consumers filtered to
    # cache membership -- see the comment on Graph::nodes()). Actions.pm
    # satisfies that contract by merge()-ing every node it builds as it
    # goes; FromOptree instead builds the whole method body against a bare
    # NodeFactory and only learns $start/$ret at the very end. Recover the
    # same membership by walking the full reachable closure from $start
    # and $ret -- inputs AND consumers, unconditionally, since every node
    # here is a real node this translate() call built (never a foreign or
    # orphan node, the reason Graph::nodes() itself must not walk consumers
    # unconditionally) -- and merge() every node the walk finds.
    #
    # A loop Phi's backedge input and the value it reads form a genuine
    # data cycle (Phi -> backedge value -> ... -> Phi). Since all objects
    # here are already fully-constructed, live Perl references (no
    # serialization order to patch, unlike the JSON loader's deferred
    # loop-Phi backedge wiring), a plain visited-set walk crosses the
    # cycle exactly once in each direction and terminates.
    #
    # start/returns MUST be passed explicitly (not left to Graph's cache-
    # scan fallback): a die-in-branch-arm body has BOTH an Unwind (the abort
    # exit) and a Return (the live exit) in %cache, and Graph::start()/
    # ->returns() without an explicit param scan `values %cache` -- Perl's
    # per-hash-table randomization (not just per-process; two hashes with
    # identical keys in the SAME process can iterate in different orders)
    # would make $g->returns->[0] pick whichever of the two exits landed
    # first, at random. $ret is the one true function-exit Return this
    # translate() call built; passing it explicitly keeps start()/returns()
    # deterministic regardless of what the closure walk also merges in.
    sub _graph_of_reachable ($start, $ret) {
        my $graph = SoN::IR::Graph->new(start => $start, returns => [$ret]);
        my %seen;
        my @stack = ($start, $ret);
        while (@stack) {
            my $node = pop @stack;
            next unless defined $node && blessed($node);
            next if $seen{$node->id()}++;
            $graph->merge($node);
            for my $input ($node->inputs()->@*) {
                if (ref($input) eq 'ARRAY') {
                    push @stack, grep { defined $_ && blessed($_) } $input->@*;
                    next;
                }
                push @stack, $input if defined $input && blessed($input);
            }
            if ($node->can('consumers')) {
                push @stack, $node->consumers()->@*;
            }
        }
        return $graph;
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

    # Record the method name for the following entersub. The invocant stays on
    # the stack (entersub consumes it). The name SV can be a shared B::SPECIAL
    # whose value lives in the pad (the same indirection the const handler
    # resolves). State rides $ctx->{pending_method} so every walker shares it.
    sub _handle_method_named ($cv, $op, $ctx) {
        my $meth_sv = $op->meth_sv;
        if ((!$$meth_sv || $meth_sv->isa('B::SPECIAL')) && $op->targ) {
            my $padl = $cv->PADLIST;
            $meth_sv = $padl->ARRAYelt(1)->ARRAYelt($op->targ)
                if $$padl;
        }
        $ctx->{pending_method} =
            ($$meth_sv && $meth_sv->can('PV')) ? $meth_sv->PV : 'unknown';
        return;
    }

    # entersub - subroutine or method call. A method dispatch is signalled by a
    # preceding method_named (recorded on $ctx->{pending_method}); otherwise it
    # is a direct sub call. Shared by the main walk and _walk_branch/_step so a
    # (void) method call in a conditional branch arm translates identically.
    sub _handle_entersub ($cv, $op, $sim, $factory, $ctx) {
        my $args = $sim->pop_to_mark;

        if (defined $ctx->{pending_method}) {
            my $pending_method = $ctx->{pending_method};
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
            # An invocant of `$self` inside a method: the class is statically the
            # ENCLOSING class (the CV's stash), so a self-dispatch `$self->m()`
            # names that class -- without which the backend GAPs ("Call(method)
            # 'm' has no class_name"). Detect it from the ORIGINAL invocant pad's
            # padname BEFORE resolving it to a bound value (a `$self` read resolves
            # to nothing useful). This is the most common real-method dispatch
            # (e.g. chalk's Grammar Symbol to_string calls $self->is_terminal()),
            # zhi 019f5dec.
            my $self_class;
            if ($invocant
                && $invocant->isa('SoN::IR::Node::PadAccess')
                && _padname($cv, $invocant->targ) eq '$self') {
                $self_class = eval { $cv->GV->STASH->NAME };
                # The self receiver is the object instance: stamp it Object so it
                # carries a repr into the backend (which lowers a self PadAccess to
                # the method's %self pointer). Without a repr the receiver PadAccess
                # GAPs before the Call is even reached.
                $invocant->set_stamp(SoN::IR::Stamp->new(type => 'Object'))
                    if $invocant->can('set_stamp');
            }
            if ($invocant
                && $invocant->isa('SoN::IR::Node::PadAccess')) {
                my $bound = $sim->lookup($invocant->targ);
                $invocant = $bound if defined $bound;
            }
            # The backend requires class_name ON the method Call node.
            # Class->new: the bareword constant invocant names the class.
            # $obj->meth: the invocant resolves to the constructor Call,
            # which carries the class_name -- propagate it.
            # $self->meth: the enclosing class, captured above.
            my $class_name;
            if (defined $self_class) {
                $class_name = $self_class;
            }
            elsif ($invocant
                && $invocant->isa('SoN::IR::Node::Constant')
                && ($invocant->const_type // '') eq 'string') {
                $class_name = $invocant->value;
            }
            elsif ($invocant
                && $invocant->isa('SoN::IR::Node::Call')
                && defined $invocant->class_name) {
                $class_name = $invocant->class_name;
            }
            # Class->new(k => v, ...): the args after the invocant are a
            # param=>value kv-list. Split the keys onto param_names and
            # the values onto inputs, so the backend binds each value to
            # its named field (a flat kv-list leaves param_names empty
            # and the constructor stores field defaults). Guarded on a
            # statically-known class and an even-length list of constant
            # keys; anything else stays a generic dispatch.
            my @call_inputs = ($invocant, $args->@*);
            my $param_names;
            if (defined $class_name && $pending_method eq 'new'
                && (($args->@*) % 2 == 0)) {
                my (@keys, @vals, $ok);
                $ok = 1;
                for (my $i = 0; $i < $args->@*; $i += 2) {
                    my ($k, $v) = ($args->[$i], $args->[$i + 1]);
                    unless ($k && $k->isa('SoN::IR::Node::Constant')
                            && ($k->const_type // '') eq 'string') {
                        $ok = 0; last;
                    }
                    push @keys, $k->value;
                    push @vals, $v;
                }
                if ($ok) {
                    $param_names = \@keys;
                    @call_inputs = @vals;   # class rides as class_name
                }
            }
            # Every call is a control-chain effect, void or not (R1.0
            # effect-by-default): pin control_in unconditionally so it is
            # ordered and survives DCE. A void call's result is discarded and
            # not pushed; a value call pushes its result on top of that same
            # control pin.
            my $void = ($op->flags & 3) == 1;   # OPf_WANT_VOID
            # A constructor (Class->new) returns the constructed object
            # instance; stamp it Object so the shape/repr contract holds.
            my $ctor = defined $class_name && $pending_method eq 'new';
            my $node = $factory->make('Call',
                inputs        => \@call_inputs,
                dispatch_kind => 'method',
                name          => $pending_method,
                (defined $class_name ? (class_name => $class_name) : ()),
                (defined $param_names ? (param_names => $param_names) : ()),
                ($ctor ? (stamp => SoN::IR::Stamp->new(type => 'Object')) : ()),
            );
            $node->set_control_in($sim->control);
            $sim->set_control($node);
            $sim->push_node($node) unless $void;
            $ctx->{pending_method} = undef;
            return;
        }

        # Direct sub call: the last arg is the callee, the rest are args.
        my $cv_node   = $args->@* ? pop $args->@* : undef;
        my $call_name = 'unknown';
        if ($cv_node && $cv_node->isa('SoN::IR::Node::Constant')) {
            $call_name = $cv_node->value // 'unknown';
        }
        # Resolve the callee to its fully-qualified name (STASH::NAME)
        # from the entersub's own callee op, so the Call names the same
        # key (main::foo) the producer keys the callee graph under. The
        # gv-handler Constant only carries the short NAME; qualifying it
        # here (in the entersub's known callee context) avoids touching
        # package-variable reads that share a name with a sub.
        if (my $callee_gv = _entersub_callee_gv($cv, $op)) {
            $call_name = $callee_gv->STASH->NAME . '::' . $callee_gv->NAME;
        }
        # Every call is a control-chain effect, void or not (R1.0
        # effect-by-default): pin control_in unconditionally so it is ordered
        # and survives DCE, exactly as the method branch does (zhi
        # 019f2dee/019f2df7). A void call's result is discarded and not
        # pushed; a value call pushes its result on top of that same control
        # pin. Without the unconditional pin a non-void call had no control
        # edge at all and was unreachable from Return, so it vanished
        # silently (F4) or floated to its value-use site and reordered past
        # a following effect (F3).
        my $void = ($op->flags & 3) == 1;   # OPf_WANT_VOID
        my $node = $factory->make('Call',
            inputs        => [ ($args->@* ? $args->@* : ()) ],
            dispatch_kind => 'direct',
            name          => $call_name,
        );
        $node->set_control_in($sim->control);
        $sim->set_control($node);
        $sim->push_node($node) unless $void;
        return;
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

        # Method / sub call. Shared with the main walk via the same handlers;
        # $ctx->{pending_method} carries the dispatch name from method_named to
        # the following entersub. Lets a (void) method call inside a branch arm
        # (_walk_branch) or loop body translate exactly as on the main path
        # (zhi 019f2df7 -- a void `$c->inc` in a conditional arm was dropped).
        if ($name eq 'method_named') {
            _handle_method_named($cv, $op, $ctx);
            return ($op->next, 'handled');
        }
        if ($name eq 'entersub') {
            _handle_entersub($cv, $op, $sim, $factory, $ctx);
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
                my $elem = $factory->make('Subscript',
                    inputs => [$args, $idx, $sim->memory]);
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

        # Handle `scalar` over an aggregate: `scalar @a` / `scalar %h` imposes
        # scalar context and yields the element count (a Length), NOT the
        # aggregate. Its kid is an aggregate producer (padav/padhv/rv2av/rv2hv),
        # which has already pushed the aggregate node onto the stack; pop it and
        # push a Length. A `scalar $x` over a genuine scalar is a pure context
        # hint and falls through to the SKIP below (leaving the scalar in place).
        # Checked before is_skip, which maps `scalar` to SKIP unconditionally.
        if ($name eq 'scalar' && $op->can('first')
            && $op->first->name =~ /^(padav|padhv|rv2av|rv2hv)$/) {
            my $agg = $sim->pop_node;
            # Only wrap a genuine aggregate. A symbolic array-deref over a
            # non-ref (`scalar @$str`, invalid under strict refs) leaves a
            # scalar Constant on the stack; Length-wrapping it would take a
            # string byte-length -- a miscompile. Fall through to SKIP (leaving
            # the value in place) unless the operand is an aggregate.
            if (_is_aggregate_node($agg)) {
                my $stamp = _result_stamp('Length', [$agg]);
                my %extra = defined $stamp ? (stamp => $stamp) : ();
                $sim->push_node($factory->make('Length', inputs => [$agg], %extra));
            }
            else {
                $sim->push_node($agg);
            }
            return ($op->next, 'handled');
        }

        # av2arylen ($#array): the array's LAST INDEX, i.e. Length - 1 (NOT the
        # length -- OpMap once mapped it to Length, a silent off-by-one: `$#a`
        # for a 3-element array is 2, not 3; `for my $i (0..$#a)` then ran one
        # extra iteration). The array was pushed by the preceding padav/rv2av.
        # An empty array yields -1 (len 0 - 1), matching perl.
        if ($name eq 'av2arylen' && $sim->stack_depth > 0
                && _is_aggregate_node($sim->peek_node)) {
            my $agg = $sim->pop_node;
            my $len = $factory->make('Length',
                inputs => [$agg],
                stamp  => SoN::IR::Stamp->new(type => 'Int'));
            my $one = $factory->make('Constant',
                value => 1, const_type => 'integer',
                stamp => SoN::IR::Stamp->new(type => 'Int'));
            $sim->push_node($factory->make('Subtract',
                inputs => [$len, $one],
                stamp  => SoN::IR::Stamp->new(type => 'Int')));
            return ($op->next, 'handled');
        }

        # rv2av dereferences an array-ref in LIST context (OPf_WANT_LIST) as an
        # assignment source, and must flatten to the referent's elements so the
        # trailing aassign builds the array from N values -- not
        # ArrayRef(ArrayRef(...)), which makes `scalar @b` return 1 (a silent
        # miscompile). Two kid shapes reach here:
        #   const[AV]: `my @q = (1..4)` -- the const handler expanded the folded
        #     AV into an ArrayRef (zhi 019f5942).
        #   padsv:     `my $r=[1,2,3]; my @b=@$r` -- the padsv resolved $r to its
        #     bound ArrayRef (zhi 019f5e42).
        # In both the popped node is an ArrayRef we flatten. A padsv bound to a
        # RUNTIME ref (not a literal ArrayRef node -- e.g. `my ($r)=@_; @$r`)
        # cannot be statically flattened; leaving the single ref as one element
        # is a silent miscompile, so GAP loudly. A SCALAR-context rv2av (`scalar
        # @$r`) is handled by the scalar-of-aggregate path above, so gate on
        # OPf_WANT_LIST here. A genuine `my @a = ([1,2,3])` (anonlist, NO rv2av)
        # is untouched.
        if ($name eq 'rv2av'
                && $op->can('first') && ${$op->first}
                && ($op->first->name eq 'const' || $op->first->name eq 'padsv')
                && ($op->flags & 3) == 3          # OPf_WANT_LIST
                && $sim->stack_depth > 0) {
            my $top = $sim->pop_node;
            if ($top->operation eq 'ArrayRef') {
                $sim->push_node($_) for $top->inputs->@*;
            }
            elsif ($op->first->name eq 'const') {
                $sim->push_node($top);   # not a const-range ArrayRef: leave as-is
            }
            else {
                die "GAP: list-context deref of a runtime array-ref (\@\$r where "
                  . "\$r is not a literal ArrayRef) not yet lowered\n";
            }
            return ($op->next, 'handled');
        }

        # A PACKAGE array/hash (`@x`, `%h`) reaches here as rv2av/rv2hv over a
        # `gv`. The gv handler pushed the variable's NAME as a string Constant
        # (it is the callee name for an entersub), and rv2sv pops that Constant
        # and replaces it with a StashAccess for a package SCALAR -- but no
        # equivalent exists for an aggregate, so the NAME STRING was left on the
        # stack and flowed into whatever consumed the array.
        #
        # That is a SILENT MISCOMPILE, not a missing feature. `$#x` became
        # Length(Constant("x")) -- the length of the variable's NAME -- so it
        # answered 1 for every package array regardless of contents. Measured:
        # @x unset -> perl -1, chalk 1; one element -> perl 0, chalk 1; two
        # elements -> perl 1, chalk 1. It agrees with perl at exactly two
        # elements, which is why t/base/term.t's `$#x` check (its array holds
        # exactly two) would have passed by coincidence.
        #
        # Two package aggregates ARE modeled and stay exempt, and between them
        # they show what the general case is missing:
        #   @_        _args_source builds a StashAccess for *main::_ -- a real
        #             array source rather than a name string.
        #   %ENV      pushed FULLY QUALIFIED as "main::ENV" (see the gv handler)
        #             so a later helem reads the process environment.
        # A general package aggregate needs module-level storage, the analogue
        # of the two-slot Str package scalar. Until that exists, refuse loudly.
        # A package AGGREGATE is an ordinary SSA variable, exactly as a package
        # SCALAR is: bound in the same %scope map under a QUALIFIED KEY, since
        # %scope takes any key and a name works there just like a pad index.
        # `our` and `my` differ in visibility and lifetime, not in modelling --
        # and the lexical handler (padav/padhv) is already name-agnostic:
        # lookup($targ) / define($targ, ...) and nothing else.
        #
        # This mirrors the gvsv/rv2sv branch below, including its lvalue split.
        # What it must NOT do is leave the gv's NAME Constant on the stack: that
        # was the old miscompile, `$#x` becoming Length(Constant("x")) -- the
        # length of the NAME -- which answers 1 for EVERY package array. A
        # 2-element array agrees with that by coincidence, which is exactly what
        # t/base/term.t checks, so the feature could be wholly broken while
        # term.t passed. The name Constant is popped here.
        #
        # @_ and %ENV keep their existing sources: _args_source builds the
        # arg-array StashAccess, and main::ENV is the process environment rather
        # than a package hash.
        if (($name eq 'rv2av' || $name eq 'rv2hv')
                && $op->can('first') && ${$op->first}
                && $op->first->name eq 'gv'
                && $sim->stack_depth > 0
                && do {
                    my $top = $sim->peek_node;
                    defined $top
                        && $top->operation eq 'Constant'
                        && defined $top->value
                        && $top->value ne '_'
                        && $top->value ne 'main::ENV';
                }) {
            my $gv      = _op_gv($cv, $op->first);
            my $gv_name = $gv && $gv->NAME;
            die "GAP: package array/hash with an unresolvable GV not yet lowered\n"
                unless defined $gv_name;

            # `local @x` has the same unwired-restore problem as `local $g`:
            # the temporary binding would outlive the scope meant to confine it.
            die "GAP: `local` on a package array/hash not yet lowered -- the"
              . " temporary binding must be restored at scope exit\n"
                if $op->private & 128;   # OPpLVAL_INTRO

            # Discard the gv's NAME Constant: it is the callee-name token an
            # entersub consumes, not a value.
            $sim->pop_node;

            # Sigil-qualified, as the scalar site is: one stash can hold
            # `$g` and `@g` as unrelated variables.
            my $agg_sigil = $op->name eq 'rv2hv' ? '%' : '@';
            my $key      = $gv->STASH->NAME . '::' . $agg_sigil . $gv_name;
            my $existing = $sim->lookup($key);

            # An LVINTRO target (`our @x = ...`) or an OPf_MOD use is a
            # DEFINITION site: push a fresh StashAccess as the name token the
            # following aassign defines from. A plain read of a bound name
            # pushes the bound VALUE, exactly as padav does.
            #
            # OPf_REF alone is NOT a definition -- it means the consumer wants
            # the AGGREGATE ITSELF rather than a flattened list. `$#x` is
            # exactly that shape (rv2av sKR/1 feeding av2arylen), and treating
            # it as a target pushed a fresh StashAccess instead of the bound
            # ArrayRef, so the length had nothing to measure. Measured: `$#x`
            # GAPped on Length.operand for every array size.
            my $is_target = ($op->private & 0x80)      # OPpLVAL_INTRO
                         || ($op->flags & 0x20);       # OPf_MOD
            if ($existing && !$is_target) {
                $sim->push_node($existing);
            }
            else {
                my $node = $factory->make('StashAccess',
                    stash_name => $gv->STASH->NAME,
                    sigil      => $agg_sigil,
                    var_name   => $gv_name);
                $sim->define(_stash_key($node), $node) unless defined $existing;
                $sim->push_node($node);
            }
            return ($op->next, 'handled');
        }

        # A REFERENCED variable cannot stay in value-SSA: a write through the
        # reference must be visible to every later read of the name, which a
        # value binding cannot express. The trigger is the reference itself,
        # NOT whether it escapes --
        #
        #   my $x = 5; my $r = \$x; $$r = 9; print $x;
        #
        # never leaves the compiled region, and is still wrong under a value
        # binding. An escape analysis would pass it.
        #
        # Every SSA IR draws the line in the same place: LLVM promotes an alloca
        # only when it is used SOLELY by loads and stores (an address-taken but
        # non-escaping alloca is not promoted); GCC gives an aliased variable
        # virtual operands (VDEF/VUSE) rather than a real SSA name; Go and
        # Cranelift do not promote `addrtaken` locals. Escape governs where the
        # storage lives and how long, not whether it is needed.
        #
        # What is missing is the DEMOTION, not a representation. An EPHEMERAL
        # scalar -- an SSA value flowing through the graph -- needs no memory
        # form. A STORED one has a static Chalk type, which maps to an LLVM type,
        # which IS its memory representation (i64, double, {i8*,i64}); the
        # `@pkg_*` globals are already that, just mis-scoped, applied to every
        # package scalar rather than only to the ones that must live in memory.
        #
        # Two pieces are genuinely absent: the decision of WHICH variables are
        # address-taken, and scalar load/store threaded on the memory chain
        # (chalk's memory-SSA threads aggregate ELEMENT accesses today). Note a
        # demoted variable is a CELL, so it has ONE type -- the join over its
        # stores, with a coercion at each -- unlike an SSA value, which carries
        # its own type per definition.
        #
        # Refuse at the point the reference is TAKEN, which is the durable
        # fence. `\$g` currently dies later in the backend ("cannot lower
        # op=Ref"), but that guard is about Ref in general: the day Ref lowers
        # for anon refs, a reference to a variable would slip through and alias
        # a value rather than a location -- writes through it silently lost.
        #
        # Read the KID op, not the stack: `\$x` marks its padsv OPf_REF|OPf_MOD,
        # but `\$g`'s gvsv carries neither, so under SSA the stack holds the
        # bound VALUE and no longer says which name it came from. An anonymous
        # ref (`[1,2]` -> anonlist, `\"hi"` -> a folded const) never reaches
        # srefgen at all, so nothing here touches it.
        if ($name eq 'srefgen' && $op->can('first') && ${$op->first}) {
            # The referent sits under one or more NULLED ex-list wrappers
            # (measured: `\$x` is srefgen -> null -> padsv, `\$g` is
            # srefgen -> null -> null -> gvsv), so descend through them.
            my $kid = $op->first;
            $kid = $kid->first
                while $$kid && $kid->name eq 'null'
                    && $kid->can('first') && ${$kid->first};
            if ($$kid && $kid->name =~ /\A(?:gvsv|padsv)\z/
                || ($kid->name eq 'rv2sv' && $kid->can('first')
                    && ${$kid->first} && $kid->first->name eq 'gv')) {
                die "GAP: taking a reference to a variable makes it"
                  . " address-taken; it must be demoted from value-SSA to"
                  . " memory, and scalar demotion is not built yet\n";
            }
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
            # A folded constant ARRAY (`(1..4)` constant-folds to a const[AV
            # ARRAY]) is not a scalar Constant -- it is an aggregate. _extract_const
            # would read only its FIRST element (a miscompile: `my @q=(1..4);
            # scalar @q` -> 1). Expand every AV element into a Constant and build
            # the equivalent N-element ArrayRef, matching the anonlist path.
            if ($$sv && $sv->isa('B::AV')) {
                my @elems = map {
                    my ($v, $st, $ct) = _extract_const($_);
                    $factory->make('Constant',
                        value => $v, stamp => $st, const_type => $ct);
                } $sv->ARRAY;
                my $arr = $factory->make('ArrayRef', inputs => \@elems);
                $sim->push_node($arr);
                return ($op->next, 'handled');
            }
            # A folded constant HASH list is likewise an aggregate, not a scalar;
            # its key/value expansion is not yet lowered -- refuse loudly.
            if ($$sv && $sv->isa('B::HV')) {
                die "GAP: constant hash literal (a folded const HV) not yet lowered\n";
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
            # A deref padsv ($r->[0], $r->{k}) carries OPf_MOD for
            # autovivification but is READING $r to dereference it -- resolve
            # it to the bound value (the ref), not a fresh lvalue PadAccess, so
            # the following rv2av/rv2hv+aelem/helem sees the aggregate.
            my $is_deref  = ($op->private & 48); # OPpDEREF (AV|HV|SV)
            my $is_lvalue = ($op->flags & 32) && !$is_deref; # OPf_MOD
            my $existing = $sim->lookup($targ);

            # A bare `my $a;` -- a padsv that INTRODUCES the slot (OPpLVAL_INTRO)
            # in VOID context, with no store following -- declares a variable
            # whose value is undef. Perl is unambiguous about this, and Undef is
            # a first-class representation, so bind it to an Undef constant
            # rather than an unstamped PadAccess.
            #
            # Leaving it untyped made `my $a; $a // 9` reach the backend with an
            # untyped DefinedOr, which looked like a defective merge: the join of
            # an unknown and an Int is unknown. The merge was computing the right
            # answer from a wrong input -- inference had simply never assigned
            # the declaration a type. An initialised `my $a = ...` is a
            # padsv_store or a following sassign and never reaches here in void
            # context.
            if (($op->private & 128)            # OPpLVAL_INTRO
                    && ($op->flags & 3) == 1    # OPf_WANT_VOID: no consumer
                    && !defined $existing) {
                my $undef = $factory->make('Constant',
                    value      => undef,
                    const_type => 'undef',
                    stamp      => SoN::IR::Stamp->new(type => 'Undef'));
                $sim->define($targ, $undef);
                return ($op->next, 'handled');
            }

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
            # A LIST-context read of an existing array as an assignment SOURCE
            # (`my @b = @a`, `my @b = (@a, 4)`) FLATTENS its elements onto the
            # stack, so the trailing aassign collects the N values and builds @b
            # from them -- NOT ArrayRef(ArrayRef(...)), which made `scalar @b`
            # return 1 (a silent miscompile, zhi 019f5deb). Same list-flatten as
            # the rv2av-over-const-AV path above, for a bare array variable.
            #
            # The flag combination distinguishes a flatten SOURCE from an op that
            # wants the AGGREGATE itself. A source has OPf_WANT_LIST (3), no
            # OPf_MOD/OPf_REF (0x20/0x10 -- set when the parent op modifies or
            # takes a reference to the array: `shift @q`/`pop @q`/`push @q`), and
            # is not an LVINTRO target (0x80). A SCALAR read (`scalar @a`,
            # `my $n = @a`) is OPf_WANT_SCALAR (2) and keeps the aggregate for its
            # Length; a shift/pop operand keeps the ArrayRef for the builtin.
            my $want        = $op->flags & 3;         # OPf_WANT: 3=list 2=scalar
            my $ref_or_mod  = $op->flags & 0x30;      # OPf_REF | OPf_MOD
            my $is_lvintro  = $op->private & 0x80;    # OPpLVAL_INTRO (target)
            if ($name eq 'padav' && $existing && $want == 3
                    && !$ref_or_mod && !$is_lvintro
                    && $existing->operation eq 'ArrayRef') {
                $sim->push_node($_) for $existing->inputs->@*;
                return ($op->next, 'handled');
            }
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
        # The %ENV stash (main::ENV) is pushed FULLY QUALIFIED so a later helem
        # can tell the process environment from a package hash whose short name
        # is also ENV (%Foo::ENV) -- the bare NAME "ENV" is ambiguous. Only
        # main::ENV is the environment; any other stash is a normal hash.
        if ($name eq 'gv') {
            my $gv = _op_gv($cv, $op);
            my $value = 'unknown';
            if ($gv) {
                # A callee gv (gv[IV \&main::foo]) resolves via a CV-ref; qualify
                # it to STASH::NAME so a direct-call Call node names the same key
                # (main::foo) the producer keys the callee graph under. %ENV stays
                # fully qualified for the same disambiguation reason; every other
                # gv keeps its short NAME (the existing StashAccess contract).
                $value = ($gv->STASH->NAME eq 'main' && $gv->NAME eq 'ENV')
                    ? 'main::ENV'
                    : $gv->NAME;
            }
            # `@_` is the ARGUMENT LIST, not a name. `$_[0]` reaches it as
            # gv[*_] under an rv2av, and this handler pushed the NAME as a
            # string Constant -- so the array was represented three different
            # ways across the IR (StashAccess for `shift`, a bare Constant
            # here, and nothing at all for `my (...) = @_`). Push the real
            # source node instead, so every spelling of `@_` names one thing.
            #
            # Guarded on the stash: a package variable genuinely called `_` in
            # some OTHER package is not the argument list.
            if ($gv && $gv->NAME eq '_' && $gv->STASH->NAME eq 'main') {
                $sim->push_node(_args_source($factory));
                return ($op->next, 'handled');
            }
            my $node = $factory->make('Constant',
                value      => $value,
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
                # A package scalar is an ordinary SSA variable, bound in the
                # SAME scope map as a lexical -- `our` and `my` differ in
                # visibility and lifetime, not in typing. %scope takes any key,
                # so a qualified name works exactly like a pad index, and
                # merge() builds Phis over it unchanged.
                #
                # This mirrors the padsv handler: an lvalue (OPf_MOD, minus the
                # deref case, which READS the ref to dereference it) pushes a
                # fresh StashAccess as a NAME TOKEN for sassign to define from;
                # an rvalue over a bound name pushes the bound VALUE.
                #
                # The StashAccess that survives is the ENTRY DEFINITION: the
                # variable's incoming value at unit entry, before any assignment
                # in this unit. Every later definition is an ordinary SSA value.
                # `local $g` is a TEMPORARY SCOPE CHANGE: within the enclosing
                # dynamic scope the name is bound to the new value, and the
                # previous binding is restored on exit. That is an ordinary
                # scope operation over the binding map -- save the binding for
                # this key, define the new one, restore the saved one at scope
                # exit -- not something the SSA model lacks a shape for.
                #
                # It is GAPped because the restore is not WIRED YET, and the
                # binding therefore outlives the scope meant to confine it.
                # Measured, and already true before package scalars became SSA:
                #
                #   our $g = 1; { local $g = 5; } print $g
                #     perl: 1     chalk: 5      -- a silent wrong answer
                #
                # Wiring it needs the restore at EVERY scope exit, not just the
                # bare block's leaveloop: a sub body, an if/else arm, a loop
                # body and a `do` block each end differently, and covering one
                # shape would leave the others silently wrong. A GAP for all of
                # them is strictly better than correct for one.
                #
                # Discriminator (measured, perl 5.42): `local` sets
                # OPpLVAL_INTRO on the gvsv (private 0x80). A plain assignment
                # is 0x00, and an `our $g = 5` declaration-plus-assignment is
                # 0x40, so neither is caught here.
                die "GAP: `local` on a package scalar not yet lowered -- the"
                  . " temporary binding must be restored at scope exit\n"
                    if $op->private & 128;   # OPpLVAL_INTRO

                # SIGIL-QUALIFIED: `$g` and `@g` are different variables
                # in one stash, and `$_` vs `@_` is the case that bites --
                # a name-only key bound the match subject and the argument
                # array to the same slot.
                my $key       = $gv->STASH->NAME . '::$' . $gv_name;
                my $is_deref  = ($op->private & 48);            # OPpDEREF
                my $is_lvalue = ($op->flags & 32) && !$is_deref; # OPf_MOD
                my $existing  = $sim->lookup($key);
                if ($existing && !$is_lvalue) {
                    $sim->push_node($existing);
                }
                else {
                    my $node = $factory->make('StashAccess',
                        stash_name => $gv->STASH->NAME,
                        sigil      => '$',
                        var_name   => $gv_name);
                    # Seed only when unbound: an lvalue over an already-bound
                    # name must not clobber it (`$g += 2` reads first).
                    $sim->define(_stash_key($node), $node) unless defined $existing;
                    $sim->push_node($node);
                }
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

            # The SUBJECT reaches a match three different ways, and only one of
            # them is the op's pad target (measured, perl 5.42):
            #   $s =~ /re/   lexical subject IS the pad target   targ=1 flags=0x02
            #   $g =~ /re/   package subject is PUSHED           targ=0 flags=0x46
            #   /re/         no binding: the subject is $_       targ=0 flags=0x02
            # Reading targ unconditionally gave the latter two a fabricated read
            # of pad slot 0 (varname "$?0"), which names no variable at all — so
            # the match tested an uninitialized slot instead of the subject.
            my $target;
            if ($op->flags & 64) {   # OPf_STACKED: subject pushed by a kid op
                # A runtime pattern ALSO arrives on the stack, so the two-value
                # order would have to be established before this could be
                # popped safely. Refuse loudly rather than guess it.
                die "GAP: a runtime pattern applied to a pushed subject "
                  . "(\$g =~ \$re) not yet lowered\n" unless defined $pattern;
                $target = $sim->pop_node;
            }
            elsif ($targ) {
                $target = $sim->lookup($targ);
                if (!$target) {
                    $target = _make_pad_or_field($cv, $targ, $factory);
                    $sim->define($targ, $target);
                }
            }
            else {
                # An unbound match reads $_ — the package scalar main::_, which
                # is an ordinary SSA variable in the scope map. Resolve it the
                # same way a `$_` READ does, so the match sees the reaching
                # definition; building a fresh StashAccess here would bypass the
                # binding and reach the backend as an untyped entry definition.
                # Keyed by SIGIL as well as name: `$_` and `@_` are
                # different variables sharing the glob name `_`, and a
                # name-only key bound them to the same slot -- which then
                # hash-consed to one node feeding both a `shift @_` and this
                # match.
                my $key = 'main::$_';
                $target = $sim->lookup($key);
                unless ($target) {
                    $target = $factory->make('StashAccess',
                        stash_name => 'main', sigil => '$', var_name => '_');
                    $sim->define($key, $target);
                }
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
        # The container and index are on the stack (index on top). Both an lvalue
        # access (OPf_MOD, the LHS of `$a[0] = ...`, which the following sassign
        # stores into) and an rvalue read yield a Subscript. A read is a real
        # memory LOAD (not a compile-time value substitution), so a preceding
        # threaded element store persists to memory and the load sees it --
        # correct under aliasing and cross-index. (A value-substitution read-back
        # cache was here; it was unsound under aliasing and is gone -- the fold is
        # deferred to a later alias-aware optimization pass.)
        if ($name eq 'aelem' || $name eq 'helem') {
            my $index     = $sim->pop_node;
            my $container = $sim->pop_node;
            my $is_lvalue = ($op->flags & 32); # OPf_MOD

            # $ENV{KEY}: a helem whose container is the %ENV stash (gv[*ENV] with
            # rv2hv transparent, so the container is the gv-name Constant, which
            # the gv handler qualified to "main::ENV" for the environment stash
            # ONLY) is a host env read, not a generic hash Subscript. A package
            # hash %Foo::ENV pushes the bare "ENV" and correctly stays a
            # Subscript. Corpus host.md H3: EnvRead(key: KEY) :Str, lowered to
            # the C getenv. Only a literal key on a read (rvalue) is recognised;
            # an lvalue $ENV{K} = ... (env write) is not modelled and falls through.
            if ($name eq 'helem' && !$is_lvalue
                && $container->isa('SoN::IR::Node::Constant')
                && ($container->value // '') eq 'main::ENV'
                && $index->isa('SoN::IR::Node::Constant')
                && defined $index->value) {
                my $node = $factory->make('EnvRead',
                    key   => $index->value,
                    stamp => SoN::IR::Stamp->new(type => 'Str'));
                $sim->push_node($node);
                return ($op->next, 'handled');
            }

            # Memory-SSA: an RVALUE read takes the current memory value as a third
            # input (memory LAST so container=[0]/index=[1] stay fixed). Pre-store
            # and post-store reads of one slot get DIFFERENT memory inputs ->
            # distinct nodes -> each observes the memory state at its program
            # point. An LVALUE Subscript (a store TARGET, OPf_MOD) is an ADDRESS,
            # not a versioned read -- it takes NO memory input, so it stays a
            # 2-input node and never hash-conses with a pre-store rvalue read of
            # the same slot (which would fold the store target and the read into
            # one node). The store path reads only inputs[0]/[1].
            my @sub_inputs = $is_lvalue
                ? ($container, $index)
                : ($container, $index, $sim->memory);
            # An RVALUE array element read at a DYNAMIC index carries the
            # container's element type (an ArrayRef of Ints reads an Int).
            # Without it, a loop accumulator over an element (`$s += $a[$i]`)
            # has an unstamped back-edge (Add($s_phi, Subscript)) that
            # _patch_loop_phi refuses ("loop-carried value loses its stamp").
            # Only stamp a DYNAMIC (non-Constant) index: a LITERAL constant index
            # must stay unstamped so the loader's _static_miss analysis can prove
            # an out-of-bounds read and re-type it as Slot (undef) -- stamping it
            # Int here would suppress that and read an OOB element as the payload
            # 0 (references R9 miscompile). A hash element or an unknown container
            # yields no element stamp -- leave it unstamped then.
            my $elem_stamp = ($name eq 'aelem' && !$is_lvalue
                    && !$index->isa('SoN::IR::Node::Constant'))
                ? _array_element_stamp($container) : undef;
            my $sub = $factory->make('Subscript',
                inputs => \@sub_inputs,
                (defined $elem_stamp ? (stamp => $elem_stamp) : ()));
            $sim->push_node($sub);
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

            # An element RMW (`$a[0]++`, `$h{k}--`): $old is the 2-input LVALUE
            # Subscript (a store ADDRESS, no memory input -- see the aelem/helem
            # handler). The arithmetic must read the PRE-store value, so build a
            # separate 3-input RVALUE read pinned to the current (pre-store)
            # memory; the lvalue Subscript stays the store target only. Reusing
            # the lvalue as the read value re-reads the slot AFTER the store-back
            # (an off-by-one / double-apply miscompile when the RMW is consumed).
            my $lvalue;
            if ($old->isa('SoN::IR::Node::Subscript')
                && scalar($old->inputs->@*) == 2) {
                $lvalue = $old;
                $old = $factory->make('Subscript',
                    inputs => [$lvalue->inputs->[0], $lvalue->inputs->[1],
                               $sim->memory]);
            }

            my $one = $factory->make('Constant',
                value => 1, const_type => 'integer',
                stamp => SoN::IR::Stamp->new(type => 'Int'));
            my $node_type = ($dir eq 'inc') ? 'Add' : 'Subtract';
            my $stamp = _result_stamp($node_type, [$old, $one]);
            my %extra = defined $stamp ? (stamp => $stamp) : ();
            my $new = $factory->make($node_type, inputs => [$old, $one], %extra);

            if (defined $lvalue) {
                # Store the new value back to the element and advance memory
                # (memory-SSA), mirroring the sassign Subscript branch. The store
                # PRODUCES the new memory value; a following read observes it.
                # Control is carried on control_in (produce-time control).
                my $store = $factory->make('Assign',
                    inputs         => [$lvalue, $new]);
                $store->set_control_in($sim->control);
                $sim->set_control($store);
                $sim->set_memory($store);
            }

            $sim->define($targ, $new) if defined $targ;
            # Pre yields the new value; post yields the old (pre-store) value.
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
            # If target is a PadAccess, update the scope binding. A sassign whose
            # RHS is an aggregate-variable read ($n = @a) imposes scalar context:
            # yield the count, like padsv_store and the explicit `scalar`
            # handler. Keyed on the RHS OP (padav/...), NOT the value node's repr
            # -- an anon-ref literal ($r = [1,2,3]) also makes an ArrayRef node
            # but is a scalar reference and must pass through.
            if ($target->isa('SoN::IR::Node::PadAccess')) {
                if (_rhs_is_aggregate_access($op) && _is_aggregate_node($value)) {
                    my $stamp = _result_stamp('Length', [$value]);
                    my %extra = defined $stamp ? (stamp => $stamp) : ();
                    $value = $factory->make('Length', inputs => [$value], %extra);
                }
                $sim->define($target->targ, $value);
                $sim->push_node($value);
            }
            # An element store (`$a[0] = 42`): the target is a Subscript lvalue.
            # This is a statement-level EFFECT -- thread the Assign onto the
            # control chain via control_in (produce-time control) so it is
            # ordered, survives DCE, and is reachable. A later read is a real
            # Subscript LOAD from the same aggregate (no compile-time read-back
            # shortcut -- see the aelem/helem read handler), so the store's
            # effect reaches memory and the load sees it. The assignment's result
            # value is the stored value, so push that as the result.
            elsif ($target->isa('SoN::IR::Node::Subscript')) {
                my $node = $factory->make('Assign', inputs => [$target, $value]);
                $node->set_control_in($sim->control);
                $sim->set_control($node);
                # The store PRODUCES a new memory value (memory-SSA): the store
                # node IS its memory-out, so a following element read takes it as
                # the read's memory input and observes the post-store state.
                $sim->set_memory($node);
                $sim->push_node($value);
            }
            # A field store (`$name = "hi"` inside a method, where $name is a
            # class field): the target is a FieldAccess lvalue. Emit an explicit
            # Assign(FieldAccess-lvalue, value) threaded onto the control chain
            # via control_in, exactly like the TARGMY field-write path -- else
            # the store is silently dropped and the field keeps its default
            # (zhi 019f2dee).
            elsif ($target->isa('SoN::IR::Node::FieldAccess')) {
                my $store = $factory->make('Assign', inputs => [$target, $value]);
                $store->set_control_in($sim->control);
                $sim->set_control($store);
                $sim->push_node($value);
            }
            # A package-scalar store (`our $g = 5`, where $g is a stash entry):
            # the target is a StashAccess lvalue. Without this branch the store
            # falls through to the catch-all below (push_node($value)), which
            # DROPS it -- a later `$g` read then loads an uninitialized slot (a
            # silent miscompile). Emit an explicit Assign(StashAccess-lvalue,
            # value) threaded onto the control chain via control_in, exactly
            # like the Subscript/FieldAccess element/field stores. Stamp the
            # lvalue StashAccess with the RHS value's OWN repr (Int for `= 5`,
            # Str for `= "hi"`) so the matching read carries the right type: the
            # store lvalue and the read hash-cons to ONE node, so stamping here
            # types both. A hardcoded Int would miscompile a Str global. Fall
            # back to Int when the RHS carries no stamp (the historical default).
            elsif ($target->isa('SoN::IR::Node::StashAccess')) {
                # An assignment is a DEFINITION, not a store into a cell: it
                # binds a new value that later reads of this name resolve to.
                # Identical to the PadAccess branch above -- the StashAccess was
                # pushed as a name token and never enters the dataflow.
                #
                # This replaces an Assign(StashAccess-lvalue, value) into a
                # typed module-level slot. That model gave one hash-consed node
                # ONE representation while each assignment carried its own, so a
                # scalar assigned two types lost the second store entirely
                # (`our $g = 1; $g = "hi"; print $g` printed 1). Under SSA each
                # definition simply has its own representation, which is why the
                # lexical path never had the bug.
                # Sigil-qualified, matching every read site: `$g` and `@g`
                # are unrelated variables in one stash, and `$_` vs `@_` is the
                # case that bit -- a name-only key bound a match subject and an
                # argument array to the same slot.
                $sim->define(_stash_key($target), $value);
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
            # padsv_store targets a SCALAR pad, so a genuine aggregate on the RHS
            # (my $n = @a) is in scalar context: yield the element count (a
            # Length), not the aggregate. Keyed on the RHS OP being an
            # aggregate-variable read (padav/... via _rhs_is_aggregate_access) --
            # the same predicate the explicit `scalar @a` handler uses -- NOT on
            # the value node's repr: an anon-ref literal (my $r = [1,2,3], an
            # anonlist) builds an identical ArrayRef node but IS a scalar
            # reference, so it must pass through unchanged.
            if (_rhs_is_aggregate_access($op) && _is_aggregate_node($value)) {
                my $stamp = _result_stamp('Length', [$value]);
                my %extra = defined $stamp ? (stamp => $stamp) : ();
                $value = $factory->make('Length', inputs => [$value], %extra);
            }
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

        # Handle multiconcat: `.=` append and string interpolation `qq{$a$b}`.
        # multiconcat is a UNOP_AUX; aux_list is [nargs, plain_pv, seglen_0 ..
        # seglen_nargs]. plain_pv is all constant text segments concatenated flat;
        # the nargs+1 seglens slice it in order (a seglen of -1 is an empty
        # segment). The nargs dynamic operands were pushed by the preceding padsv
        # ops (arg0 deepest, argN on top). The value is the left-folded chain
        #   seg[0] . arg[0] . seg[1] . arg[1] . ... . seg[nargs]
        # of binary Concat nodes (empty segments skipped). APPEND (OPpMULTICONCAT_
        # APPEND, 0x40) folds onto the current targ value ($s .= ...); otherwise
        # the fold starts at seg[0] and, with OPpLVAL_INTRO (0x80, `my $c = ...`),
        # a VarDecl wraps the new pad slot -- mirroring padsv_store's LVINTRO path.
        if ($name eq 'multiconcat' && $op->can('aux_list')) {
            my @aux    = $op->aux_list($cv);
            my $nargs  = $aux[0] // 0;
            my $plain  = ref $aux[1] ? (eval { $aux[1]->PV } // '') : ($aux[1] // '');
            my @seglen = @aux[2 .. 2 + $nargs];   # nargs+1 segment lengths

            # Slice plain_pv into segments; a seglen of -1 is an empty segment.
            my ($pos, @seg) = (0);
            for my $len (@seglen) {
                if (!defined $len || $len < 0) { push @seg, undef }
                else { push @seg, substr($plain, $pos, $len); $pos += $len }
            }

            # Pop the dynamic operands: argN is on top, arg0 deepest.
            my @args;
            unshift @args, $sim->pop_node for 1 .. $nargs;

            my $mkstr = sub ($s) {
                $factory->make('Constant',
                    value => $s, const_type => 'string',
                    stamp => SoN::IR::Stamp->new(type => 'Str'));
            };
            my $concat = sub ($l, $r) {
                $factory->make('Concat',
                    inputs => [$l, $r],
                    stamp  => SoN::IR::Stamp->new(type => 'Str'));
            };

            # Seed the accumulator with seg[0]: APPEND ($s .= ...) folds onto the
            # current $s value, so seg[0] (e.g. the "bar" of `$s .= "bar"`) appends
            # to $s; a fresh concat starts at seg[0] itself. Then interleave each
            # arg[i] with the segment that follows it (seg[i+1]).
            my $acc;
            if ($op->private & 0x40) {
                $acc = $sim->lookup($op->targ);
                $acc = $concat->($acc, $mkstr->($seg[0])) if defined $seg[0];
            }
            elsif (defined $seg[0]) { $acc = $mkstr->($seg[0]) }

            for my $i (0 .. $nargs - 1) {
                # Interpolation is COERCION: a non-Str operand is stringified
                # before it enters the Concat (or seeds the fold), so the chain
                # sees only Str inputs. Applies to a foldable Int Constant and a
                # dynamic Call alike.
                my $arg = _coerce_to_str($factory, $args[$i]);
                $acc = defined $acc ? $concat->($acc, $arg) : $arg;
                $acc = $concat->($acc, $mkstr->($seg[$i + 1])) if defined $seg[$i + 1];
            }
            $acc //= $mkstr->('');   # degenerate: no args and no non-empty segment

            my $targ = $op->targ;
            # OPpLVAL_INTRO (0x80): a new lexical (`my $c = qq{...}`). The main
            # walker wraps the pad slot in a VarDecl so the declaration is
            # reachable; the value stays the scope binding.
            if ($mode eq 'main' && ($op->private & 0x80)) {
                my $pad = _make_pad_or_field($cv, $targ, $factory);
                $factory->make('VarDecl', inputs => [$pad, $acc], scope => 'my');
            }
            $sim->define($targ, $acc);
            $sim->push_node($acc);
            return ($op->next, 'handled');
        }

        # Handle emptyavhv - the fused op modern perl emits for an empty `[]` or
        # `{}` (`my $r = []`). Unlike a non-empty `[1,2,3]` (an anonlist with a
        # pushmark and const kids), an empty aggregate has NO list op: perl fuses
        # it to a single emptyavhv that writes an empty AV/HV straight into its
        # TARGMY pad slot. The array/hash choice is the OPpEMPTYAVHV_IS_HV (0x20)
        # private flag. It must build an empty ArrayRef/HashRef (0 inputs); the
        # generic TARGMY path below would instead build a valueless Constant and
        # die -- an internal error masked as a silent skip (the whole sub vanished
        # from the output, zhi 019f5ed3).
        if ($name eq 'emptyavhv') {
            my $is_hash = $op->private & 0x20;   # OPpEMPTYAVHV_IS_HV
            my $node = $factory->make($is_hash ? 'HashRef' : 'ArrayRef',
                inputs => []);
            my $targ = $op->targ;

            # A field store (TARGMY into a class field slot) threads on control
            # via an explicit Assign, exactly like the generic TARGMY path; a pad
            # slot is an SSA rebind. LVINTRO in main mode wraps the pad in a
            # VarDecl so the `my` declaration stays reachable.
            my $lv       = _make_pad_or_field($cv, $targ, $factory);
            my $is_field = $lv->isa('SoN::IR::Node::FieldAccess');
            if ($is_field) {
                my $store = $factory->make('Assign', inputs => [$lv, $node]);
                $store->set_control_in($sim->control);
                $sim->set_control($store);
            }
            else {
                if ($mode eq 'main' && ($op->private & 0x80)) {  # OPpLVAL_INTRO
                    $factory->make('VarDecl',
                        inputs => [$lv, $node], scope => 'my');
                }
                $sim->define($targ, $node);
            }
            $sim->push_node($node);
            return ($op->next, 'handled');
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

                # A TARGMY write into a class FIELD slot (e.g. ADJUST's
                # `$double = $val * 2`) is a field store, not a plain pad rebind.
                # Emit an explicit Assign(FieldAccess-lvalue, value) so the store
                # target (fieldix) survives into the graph — the loader types the
                # field from the stored value's repr. Mirrors the corpus IR spec.
                my $lv = _make_pad_or_field($cv, $op->targ, $factory);
                my $is_field = $lv->isa('SoN::IR::Node::FieldAccess');
                if ($is_field) {
                    my $store = $factory->make('Assign', inputs => [$lv, $node]);
                    $store->set_control_in($sim->control);
                    $sim->set_control($store);
                }

                # A pad self-assign rebinds the slot in SSA scope so a later read
                # returns the new value. A FIELD, by contrast, is stored to the
                # object slot by the Assign above and re-read from that slot (like
                # element memory) -- it is NOT a pad-SSA binding. Defining it in
                # scope makes merge() build a dead value-Phi over the branch arms
                # (Phi#9) that reaches the backend with no repr (zhi 019f5368); the
                # field store already threads on control, so skip the scope rebind.
                $sim->define($op->targ, $node) unless $is_field;
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

            # Array/hash construction: `my @a = (1,2,3)` / `my %h = (k=>0)`,
            # and the `our` forms of both. The LHS is a single aggregate target;
            # bind it to an ArrayRef/HashRef of the RHS values so later element
            # access has a real container.
            #
            # A LEXICAL target is a PadAccess keyed by pad index; a PACKAGE
            # target is a StashAccess keyed by its qualified name. %scope takes
            # either, which is the whole reason a package aggregate needs no
            # separate machinery -- `our` and `my` differ in visibility and
            # lifetime, not in modelling.
            #
            # The SIGIL says which container to build. A PadAccess carries it in
            # varname ('@a'); a StashAccess does not, so it comes from the op
            # that pushed the target -- rv2av for an array, rv2hv for a hash.
            if (@$lhs == 1 && $sim->has_mark
                && ( $lhs->[0]->isa('SoN::IR::Node::PadAccess')
                  || $lhs->[0]->isa('SoN::IR::Node::StashAccess') )) {
                my $target = $lhs->[0];
                my $is_pad = $target->isa('SoN::IR::Node::PadAccess');

                my ($sigil, $key);
                if ($is_pad) {
                    $sigil = substr($target->varname, 0, 1);
                    $key   = $target->targ;
                }
                else {
                    # The aggregate op that built this target. Walk the LHS
                    # subtree for the rv2av/rv2hv rather than guessing.
                    $sigil = _stash_target_sigil($op);
                    # Sigil-qualified, matching the read sites: one stash can
                    # hold `$g` and `@g` as unrelated variables.
                    $key   = _stash_key($target);
                }

                if (defined $sigil && ($sigil eq '@' || $sigil eq '%')) {
                    my $rhs = $sim->pop_to_mark;
                    my $node = $factory->make(
                        ($sigil eq '@' ? 'ArrayRef' : 'HashRef'),
                        inputs => [$rhs->@*]);
                    $sim->define($key, $node);
                    $sim->push_node($node);
                    return ($op->next, 'handled');
                }
            }

            # Fallback: a generic list assignment.
            my $node = $factory->make('Assign', inputs => [$lhs->@*]);
            $sim->push_node($node);
            return ($op->next, 'handled');
        }

        # print LISTOP: emit a Print node over the whole argument list, control-
        # pinned (a bare `print` is OPf_WANT_VOID, an ordered stdout effect that
        # must survive DCE). The list is a pushmark..print span; pop_to_mark
        # gathers every element as an input. print yields 1, so the Print node is
        # also usable as a value.
        #
        # An explicit filehandle (`print STDOUT ...` / `print $fh ...`) sets
        # OPf_STACKED (0x40) and pushes a gv/rv2gv onto the stack before the
        # args -- a LOUD GAP, never a silent misroute to fd 1: the runtime-free
        # backend writes only to stdout, so honoring an explicit handle would be
        # a miscompile.
        # A bare `stringify` op ("$x" on its own -- an interpolation of exactly
        # one operand and nothing else) is the X->Str coercion spelled by perl.
        # Handled here rather than through OpMap because the generic path cannot
        # supply Coerce's from_repr/to_repr; it mapped to a Stringify node,
        # which is the same edge under a second name.
        if ($name eq 'stringify') {
            $sim->push_node(_coerce_to_str($factory, $sim->pop_node));
            return ($op->next, 'handled');
        }

        # `say` IS `print` with a trailing newline -- desugared here rather than
        # given its own node, so every downstream consumer (the control pin, the
        # effect predicates, the backend's _lower_print) sees one operator. Its
        # OpMap entry maps it to a generic Call, which this branch pre-empts.
        if ($name eq 'print' || $name eq 'say') {
            if ($op->flags & 64) {   # OPf_STACKED: an explicit filehandle operand
                die "GAP: $name to an explicit filehandle ($name FH ... / "
                  . "$name \$fh ...) is not lowered -- the runtime-free backend "
                  . "writes only to stdout; honoring a handle would misroute.\n";
            }
            my $args = $sim->pop_to_mark;
            my @inputs = $args->@*;

            # The newline is appended as an ordinary Str operand, so a `say`
            # lowers through exactly the same path a `print LIST, "\n"` does.
            push @inputs, $factory->make('Constant',
                value      => "\n",
                const_type => 'string',
                stamp      => SoN::IR::Stamp->new(type => 'Str'))
                if $name eq 'say';

            # Print's signature is Print(Str...). A non-Str argument is COERCED
            # to Str, exactly as Divide's Int operands are coerced to Num --
            # rather than Print growing a case per representation. That keeps
            # the type knowledge in ONE place: only the coercion learns a type,
            # and Print stays one operator over one representation.
            #
            # An UNSTAMPED argument is left alone: coercing it would be a guess
            # about a type nothing has established, and the backend still has to
            # answer for it.
            @inputs = map {
                my $st = $_->can('stamp') ? $_->stamp : undef;
                defined $st ? _coerce_to_str($factory, $_) : $_;
            } @inputs;

            # Void statement position (the only shape wired): control-pin via
            # control_in (produce-time control) so the stdout effect is
            # ordered and survives DCE, mirroring the I1 void-effect path.
            my $is_effect = defined $sim->control;
            my $node = $factory->make('Print', inputs => \@inputs);
            if ($is_effect) {
                $node->set_control_in($sim->control);
                $sim->set_control($node);
            }

            # print returns 1; push it so a value context (`my $ok = print ...`)
            # reads the return. A void print's pushed value is dead and dropped
            # by the surrounding nextstate, exactly like the void-effect Call.
            $sim->push_node($node) unless (($op->flags & 3) == 1);  # OPf_WANT_VOID
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

                # push/unshift/splice MUTATE their array's length. shift/pop are
                # memory-SSA modeled below (the Call becomes the new memory
                # version, so a later whole-array read observes the mutation),
                # but these are not: the generic Call built here does NOT thread
                # onto @a's memory version, so a later `scalar @a` reads the
                # PRE-mutation binding and returns the old length -- a silent
                # miscompile (`my @b=@a; push @b,3; scalar @b` -> 2 not 3;
                # `splice(@a,1,1); scalar @a` -> 3 not 2). GAP loudly per
                # GAP-not-miscompile until the length mutation is memory-modeled
                # like shift/pop. zhi 019f5e42 (push/unshift), 019f5ed3 (splice).
                if ($node_type eq 'Call'
                        && ($name eq 'push' || $name eq 'unshift'
                            || $name eq 'splice')) {
                    die "GAP: $name (array length mutation) not yet lowered -- "
                      . "the new length is not observed by a later read.\n";
                }

                # shift/pop MUTATE their array (remove an element) and yield the
                # removed value. Model as a memory statement effect (mirrors the
                # element-store path): the current memory leads the inputs,
                # control_in orders it on the control chain (produce-time
                # control), and the Call becomes the new memory version so a
                # later whole-array read (Length/element) observes the drained
                # array. Stamp with the array's element type so the removed
                # value (and anything derived from it) carries a repr.
                if ($node_type eq 'Call' && ($name eq 'shift' || $name eq 'pop')
                        && @inputs == 1 && _is_aggregate_node($inputs[0])
                        && defined $sim->control && defined $sim->memory) {
                    my $elem_stamp = _array_element_stamp($inputs[0]);
                    my $call = $factory->make('Call',
                        inputs         => [$inputs[0], $sim->memory],
                        dispatch_kind  => 'builtin',
                        name           => $name,
                        (defined $elem_stamp ? (stamp => $elem_stamp) : ()));
                    $call->set_control_in($sim->control);
                    $sim->set_control($call);
                    $sim->set_memory($call);
                    $sim->push_node($call) if $push_count;
                    return ($op->next, 'handled');
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

                # Field compound assignment (`$n += 1` in a method): the FIRST
                # operand is a class-field read (FieldAccess) whose padsv carries
                # OPf_MOD and the op is the STACKED `op=` form. The field lives in
                # the object struct, so the += result must be written back via an
                # Assign(FieldAccess-lvalue) store -- the same store the `$n = $n +
                # 1` TARGMY path emits. Without it the temp result (the add targets
                # a temp, not the field) is dropped and the mutation is lost.
                my $field_compound =
                       @inputs >= 1
                    && $inputs[0]->isa('SoN::IR::Node::FieldAccess')
                    && ($op->flags & 64)          # OPf_STACKED (the op= form)
                    && $op->can('first')
                    && $op->first->name =~ /^padsv/
                    && ($op->first->flags & 32);  # OPf_MOD (lvalue read)

                # Element compound assignment (`$a[0] += 5`): the FIRST operand
                # is a 2-input lvalue Subscript (a store ADDRESS) and the op
                # carries OPf_STACKED (0x40, the `op=` form -- a plain `$a[0]+$x`
                # has no STACKED). Read-modify-write the element: the arithmetic
                # must read the PRE-store value, so swap in a 3-input rvalue read
                # pinned to the current memory; the lvalue stays the store target.
                my $elem_lvalue;
                if (!$is_compound
                    && @inputs >= 1
                    && $inputs[0]->isa('SoN::IR::Node::Subscript')
                    && scalar($inputs[0]->inputs->@*) == 2
                    && ($op->flags & 64)) { # OPf_STACKED
                    $elem_lvalue = $inputs[0];
                    $inputs[0] = $factory->make('Subscript',
                        inputs => [$elem_lvalue->inputs->[0],
                                   $elem_lvalue->inputs->[1], $sim->memory]);
                }

                my $stamp = _result_stamp($node_type, \@inputs);
                $extra{stamp} = $stamp if defined $stamp;

                # Effect-by-default for generic builtin Calls. Chalk's effect
                # classifier defaults a Call to PURE (floatable, DCE-if-value-
                # unused), so an effectful builtin (chomp/warn/print) in void
                # position had its pushed value dead and vanished silently
                # (`chomp $s; length $s` computed length of the un-chomped
                # string). Invert that here: a Call in void statement position
                # (OPf_WANT_VOID) that is NOT on the OpMap pure allow-list is
                # built control-pinned via control_in (produce-time control)
                # -- mirroring the void entersub path, so the effect is
                # ordered and survives DCE. A PURE call, or any Call whose
                # value is consumed (non-void), stays a plain floatable data
                # node (CSE/hash-consing preserved).
                #
                # substr is PURE as an rvalue but MUTATES as an lvalue
                # (substr(...)="X"); the static PURE flag cannot tell them apart.
                # The optimizer folds the assignment into the substr op in the
                # lvalue form, which carries OPf_STACKED (the same `op=`/store
                # marker the element-compound-assign path below keys on). A
                # STACKED pure Call is an in-place store, so it overrides PURE
                # and is pinned like any other effect.
                my $void_effect_call = false;
                if ($node_type eq 'Call' && defined $sim->control) {
                    my $void      = ($op->flags & 3) == 1;    # OPf_WANT_VOID
                    my $lvalue    = ($op->flags & 64);         # OPf_STACKED (store form)
                    my $effectful = !$opmap->is_pure($name) || $lvalue;
                    $void_effect_call = $void && $effectful;
                }

                # Perl `/` is always floating-point division, so an Int operand
                # must be coerced to Num before the Divide. Wrap each Int-stamped
                # operand in a Coerce(Int->Num) at BUILD time (no post-hoc graph
                # rewire) so the Divide's inputs arrive representation=Num on the
                # chalk side and TypedInvariant's `Divide => Num` requirement is
                # satisfied. Only the plain OpMap Divide is handled here; the
                # TARGMY-Divide twin (`$x /= 2`) is out of scope.
                if ($node_type eq 'Divide') {
                    @inputs = map { _coerce_int_to_num($factory, $_) } @inputs;
                }

                # There is ONE Add (likewise Subtract/Multiply) and its signature
                # is (Num, Num) -> Num. Int <: Num, so an all-Int application IS
                # a Num application -- its result is in Int, so the narrower i64
                # representation is kept and a 64-bit integer loses no precision.
                # Emitting `add i64` there is a representation choice (an
                # optimization), not a second, integer-specific operator.
                #
                # A MIXED application is where the representations genuinely
                # differ, and that is exactly where a coercion belongs: the Int
                # operand gets an explicit Coerce(Int->Num), the same treatment
                # Divide gets above, instead of an implicit sitofp inside the
                # backend. With the coercion in the graph the operands are
                # uniformly Num and no subtype relaxation of the invariant is
                # needed to admit them.
                # StrEq/StrNe compare STRINGS: their signature is (Str, Str), so
                # a non-Str operand is coerced -- the same treatment Print's
                # arguments get, through the same injection point. `eq` does not
                # grow a case per representation, and the backend does not carry
                # a second copy of the int-to-decimal renderer.
                if ($node_type eq 'StrEq' || $node_type eq 'StrNe') {
                    @inputs = map {
                        my $st = $_->can('stamp') ? $_->stamp : undef;
                        defined $st ? _coerce_to_str($factory, $_) : $_;
                    } @inputs;
                }

                if ($node_type eq 'Add' || $node_type eq 'Subtract'
                                        || $node_type eq 'Multiply') {
                    my $mixed = grep {
                        my $s = $_->can('stamp') ? $_->stamp : undef;
                        defined $s && $s->type eq 'Num';
                    } @inputs;
                    @inputs = map { _coerce_int_to_num($factory, $_) } @inputs
                        if $mixed;
                }
                my $node = $factory->make($node_type, inputs => \@inputs, %extra);
                if ($void_effect_call) {
                    $node->set_control_in($sim->control);
                    $sim->set_control($node);
                }

                # Rebind the target to the result so a later read sees the new
                # value.
                if ($is_compound) {
                    $sim->define($lvalue_targ, $node);
                }
                elsif ($field_compound) {
                    # Store the += result back to the field slot (memory), like
                    # the TARGMY `=` field-write path. The lvalue is a fresh
                    # FieldAccess for the same field (the first operand's padsv).
                    my $lv = _make_pad_or_field($cv, $op->first->targ, $factory);
                    my $store = $factory->make('Assign', inputs => [$lv, $node]);
                    $store->set_control_in($sim->control);
                    $sim->set_control($store);
                }
                elsif (defined $elem_lvalue) {
                    # Store the result back to the element and advance memory
                    # (memory-SSA), mirroring the sassign Subscript branch.
                    my $store = $factory->make('Assign',
                        inputs         => [$elem_lvalue, $node]);
                    $store->set_control_in($sim->control);
                    $sim->set_control($store);
                    $sim->set_memory($store);
                }

                # A void effectful call's result is discarded (OPf_WANT_VOID);
                # control was already advanced to it, and pushing its dead value
                # would leave a stray operand on the stack (the void entersub path
                # likewise pushes nothing). Every other node pushes normally.
                if ($push_count && !$void_effect_call) {
                    $sim->push_node($node);
                }
            }

            return ($op->next, 'handled');
        }

        return ($op, 'unhandled');
    }

    # _is_postfix_while($enter_op): true iff the enter/leave scope is a postfix
    # `EXPR while COND` -- i.e. the statement's and/or has a body arm (->other)
    # that ends in an `unstack` whose ->next jumps back to the condition head
    # (enter->next). A plain `enter` scope has no such back-edge. Detecting this
    # at `enter` lets the main walk delegate to _translate_while_loop's two-phase
    # scout BEFORE building any real node, so no dead pre-loop-constant
    # pre-evaluation orphans are committed (zhi 019f29ed).
    sub _is_postfix_while ($enter_op) {
        my $cond_head = $enter_op->next;
        return 0 unless $$cond_head;
        my $op = $cond_head;
        my %seen;
        while ($$op && !$seen{$$op}++) {
            my $name = $op->name;
            last if $name eq 'leave' || $name eq 'nextstate';
            if ($name eq 'and' || $name eq 'or') {
                my $arm = $op->other;
                my %aseen;
                while ($$arm && !$aseen{$$arm}++) {
                    if ($arm->name eq 'unstack') {
                        my $target = $arm->next;
                        return ($$target && $$target == $$cond_head) ? 1 : 0;
                    }
                    $arm = $arm->next;
                }
                return 0;
            }
            $op = $op->next;
        }
        return 0;
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
    # _body_writes_targ($cv, $start_op, $sim, $opmap, $targ) -> bool
    #
    # True if walking the loop body rebinds pad slot $targ (a write). Used to
    # detect a foreach body that assigns its iterator variable (an aliasing
    # write-back to the array). The scout seeds ONLY $targ with a placeholder and
    # reports whether the body rebound it -- _scout_mutated_targs cannot answer
    # this for the iterator because it excludes $extra_targs from its result and
    # only seeds slots already in scope (the iterator is not in the outer scope).
    sub _body_writes_targ ($cv, $start_op, $sim, $opmap, $targ) {
        my $scout_factory = SoN::IR::NodeFactory->new();
        my $scout_sim     = SoN::FromOptree::StackSim->new(
            control => $scout_factory->make_cfg('Start'),
            # A throwaway MemStart so a body element read (`$a[$i]`) builds a
            # Subscript with a defined memory input during scouting -- else the
            # Node ADJUST dies "consumers on undef" and B::SoN masks it as a
            # silent sub-drop.
            memory  => $scout_factory->make('MemStart'));
        # Seed the current scope so body reads resolve, plus a placeholder for
        # the iterator slot so a write to it is detectable.
        for my $t (keys $sim->scope_bindings->%*) {
            $scout_sim->define($t, $scout_factory->make_unique('Constant',
                value => 'scout', const_type => 'string'));
        }
        my $ph = $scout_factory->make_unique('Constant',
            value => 'scout-iter', const_type => 'string');
        $scout_sim->define($targ, $ph);
        _walk_loop_body($cv, $start_op, $scout_sim, $scout_factory, $opmap, {}, {});
        my $after = $scout_sim->scope_bindings->{$targ};
        return defined $after && $after != $ph;
    }

    sub _scout_mutated_targs ($cv, $start_op, $sim, $opmap, $extra_targs = []) {
        my $scout_factory = SoN::IR::NodeFactory->new();
        my $scout_sim     = SoN::FromOptree::StackSim->new(
            control => $scout_factory->make_cfg('Start'),
            # A throwaway MemStart so a body element read builds a Subscript with
            # a defined memory input during scouting (see _body_writes_targ).
            memory  => $scout_factory->make('MemStart'));
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
        return [ sort _scope_key_order
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

    # _backedge_is_phi_recurrence($post, $phi) -> bool
    #
    # True when the back-edge is a numeric arithmetic op (Add/Subtract/Multiply/
    # Divide/Modulo) that consumes $phi directly and whose OTHER inputs are each
    # either stamped or a deferred element read (a Subscript over a non-literal
    # aggregate, whose stamp the Chalk loader supplies). This is the
    # accumulator recurrence `$s = $s <op> $elem`: the result type is $phi's own
    # (numeric) type, so keeping $phi's init stamp is the fixpoint -- no widening.
    # A back-edge that is NOT arithmetic over $phi, or whose unstamped input is
    # not an element read, is a genuine unknown and still GAPs.
    my %_ARITH_OP = map { $_ => 1 } qw(Add Subtract Multiply Divide Modulo);
    sub _backedge_is_phi_recurrence ($post, $phi) {
        return false unless blessed($post) && $_ARITH_OP{$post->operation};
        my @ins = $post->inputs->@*;
        my $reads_phi = grep { blessed($_) && $_->id == $phi->id } @ins;
        return false unless $reads_phi;
        for my $in (@ins) {
            next unless blessed($in);
            next if defined $in->stamp;                 # already typed
            next if $in->id == $phi->id;                # the recurrence arm
            # An unstamped input is acceptable ONLY if it is a deferred element
            # read the loader will type.
            return false unless $in->operation eq 'Subscript';
        }
        return true;
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
            # The back-edge is unstamped only because ONE input's stamp is
            # deferred to the Chalk loader (an element read Subscript over a
            # runtime aggregate -- a FieldAccess/field-backed array, whose
            # element type lives on the loader side). RE-DERIVE the back-edge
            # stamp now against the Phi's (init) stamp, treating a deferred
            # element read as the Phi's own type: for a numeric accumulator
            # `$s = $s + $elem`, the result type is the Phi's type and the join
            # is a no-op. If the back-edge is a genuine arithmetic recurrence
            # over the Phi with one deferred input, this is a fixpoint no-op
            # (join(init, init) == init). Any OTHER unstamped shape (not
            # arithmetic over the Phi) still GAPs -- no guessing.
            if (_backedge_is_phi_recurrence($post, $phi)) {
                # The Phi keeps its init stamp; the deferred input is typed by
                # the loader, and the backend's fixpoint (loop-Phi placement)
                # sees a stamped Phi. Nothing to widen.
                return;
            }
            # The body was already stamped against this Phi's optimistic
            # init stamp; merely un-stamping the Phi here leaves those stale
            # stamps contaminating sibling Phi joins (a type-level
            # miscompile). Refuse until fixpoint restamping exists.
            die "GAP: loop-carried value loses its stamp (unstamped"
              . " back-edge); fixpoint restamping not yet lowered\n";
        }
        return;
    }

    # A loop-header condition must be an icmp for the backend to recover it
    # structurally (control_in on the Loop). These are the comparison ops; the
    # Boolean-producing ops (Defined/Not/etc.) already yield an i1 and must NOT be
    # re-wrapped in NumNe(x,0) -- that would compare an i1 as an i64 (a type
    # mismatch the backend rejects). A node with a Boolean stamp is already a
    # truthiness value.
    my %COMPARISON_OP = map { $_ => 1 }
        qw(NumEq NumLt NumGt NumLe NumGe NumNe
           StrEq StrLt StrGt StrLe StrGe StrNe
           Defined Not IsaOp Match NotMatch);
    sub _is_comparison ($node) {
        return 1 if $COMPARISON_OP{ $node->operation };
        my $stamp = $node->stamp;
        return 1 if defined $stamp && $stamp->type eq 'Boolean';
        return 0;
    }

    # Synthesize an explicit truthiness test NumNe($value, 0) for a bare-scalar
    # loop condition (`while ($n)`), so the control-wired condition is an icmp.
    sub _truthiness_test ($value, $factory) {
        my $zero = $factory->make('Constant',
            value      => 0,
            const_type => 'integer',
            stamp      => SoN::IR::Stamp->new(type => 'Int'));
        return $factory->make('NumNe',
            inputs => [$value, $zero],
            stamp  => SoN::IR::Stamp->new(type => 'Boolean'));
    }

    # The logical negation of each comparison op: NumGe negates to NumLt (over the
    # SAME operands), etc. Used to hoist a `last if COND` at the head of a
    # `while(1)` body into the loop's continuation condition -- the loop runs
    # while NOT COND, so the exit test on `last if $i >= 3` becomes the
    # continuation `$i < 3` (NumLt), an icmp the backend recovers exactly like a
    # written while-header (see _walk_loop_body's condition handler).
    my %_NEGATE_COMPARISON = (
        NumEq => 'NumNe', NumNe => 'NumEq',
        NumLt => 'NumGe', NumGe => 'NumLt',
        NumGt => 'NumLe', NumLe => 'NumGt',
        StrEq => 'StrNe', StrNe => 'StrEq',
        StrLt => 'StrGe', StrGe => 'StrLt',
        StrGt => 'StrLe', StrLe => 'StrGt',
    );

    # Negate a comparison node by swapping its op over the same operands. Returns
    # undef for any non-comparison shape (a bare-truthiness `last if $flag`),
    # which the caller GAPs -- wrapping an arbitrary value in Not would not yield
    # the icmp the backend's structural loop recovery requires.
    sub _negate_comparison ($node, $factory) {
        my $neg = $_NEGATE_COMPARISON{ $node->operation }
            or return undef;
        return $factory->make($neg,
            inputs => [ $node->inputs->@* ],
            stamp  => SoN::IR::Stamp->new(type => 'Boolean'));
    }

    # Perl evaluates a while CONDITION N+1 times: the final, FAILING evaluation
    # still applies its side effects. `while ($i-- > 0)` decrements $i on the
    # failing pass too, so the post-loop $i is the value AFTER that pass, not the
    # header Phi's exit value. Scout the condition ops alone on an insulated sim
    # (stopping at the and/or that closes the condition) and return the sorted set
    # of pad slots the condition rebinds. _translate_while_loop re-binds these
    # slots to their loop-Phi BACK-EDGE post-loop (the value after the failing
    # pass) instead of to the header Phi (the value that failed the test).
    #
    # A condition that also STORES to memory (an lvalue element `$a[$i]++` in the
    # guard) advances the memory chain on the failing pass -- the exit-path rebind
    # models only pad slots, not that memory back-edge -- so refuse loudly.
    sub _scout_condition_mutated_targs ($cv, $cond_start, $sim, $opmap) {
        my $probe = $cond_start;
        my %probe_seen;
        $probe = $probe->next
            while $$probe && !$probe_seen{$$probe}++
                && $probe->name ne 'and' && $probe->name ne 'or';
        return [] unless $$probe
            && ($probe->name eq 'and' || $probe->name eq 'or');

        die "GAP: side-effecting loop condition with a memory store not yet lowered\n"
            if _cond_stores_memory($cond_start);

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
        return [ sort _scope_key_order
            grep { defined $after->{$_} && $after->{$_} != $placeholder{$_} }
            keys %placeholder ];
    }

    # Does a loop CONDITION store to memory (an lvalue element `$a[$i]++` /
    # `$h{$k}=...` in the guard)? Scan cond_start up to the and/or that closes the
    # condition. An lvalue element (OPf_MOD set on aelem/helem, or a multideref in
    # lvalue context) is a store; a non-lvalue read is caught separately by
    # _cond_reads_memory. Stop at nextstate (a body statement boundary) so a
    # headless while(1)'s body store is not misattributed to the condition.
    sub _cond_stores_memory ($cond_start) {
        my %seen;
        for (my $op = $cond_start; $$op && !$seen{$$op}; $op = $op->next) {
            $seen{$$op} = 1;
            my $name = $op->name;
            last if $name eq 'and' || $name eq 'or';
            last if $name eq 'nextstate';
            return 1 if ($name eq 'aelem' || $name eq 'helem')
                && ($op->flags & 0x20);   # OPf_MOD -- lvalue element is a store
        }
        return 0;
    }

    # Does a loop CONDITION read memory ($a[$i] / $h{$k} in the guard)? Such a
    # read must rename through a loop-header memory-Phi, which is not yet lowered
    # for conditions. Without this guard the read either underflows the stack sim
    # (fused multideref path) or builds a Subscript with undef memory ("consumers
    # on an undefined value", unfused aelem path) -- both non-GAP errors that
    # B::SoN swallows silently, dropping the whole sub with no diagnostic. Refuse
    # LOUDLY here instead. The condition op-chain runs from cond_start up to the
    # and/or that closes it (the BODY hangs off that and/or's ->other), so scan
    # only that span. A read is a multideref (fused) or a non-lvalue aelem/helem
    # (unfused); an lvalue (OPf_MOD) element in the guard is a store, handled by
    # _assert_pure_condition's side-effect GAP.
    #
    # A real condition is a single expression: its ops start immediately at
    # cond_start (padsv/const/aelem/... then and/or) with NO leading nextstate. A
    # headless loop (while(1)) has no condition ops at all -- cond_start IS the
    # body, whose first statement opens with a nextstate. So a nextstate means we
    # have entered the body; stop before it, otherwise the scan walks into the
    # body and misblames a body memory read on the condition (a while(1) with a
    # body read is its own honest GAP downstream, not a condition read).
    sub _cond_reads_memory ($cond_start) {
        my %seen;
        for (my $op = $cond_start; $$op && !$seen{$$op}; $op = $op->next) {
            $seen{$$op} = 1;
            my $name = $op->name;
            last if $name eq 'and' || $name eq 'or';
            last if $name eq 'nextstate';   # body statement boundary -- not the condition
            return 1 if $name eq 'multideref';
            return 1 if ($name eq 'aelem' || $name eq 'helem')
                && !($op->flags & 0x20);   # OPf_MOD -- lvalue element is a store
        }
        return 0;
    }

    sub _translate_while_loop ($cv, $cond_start, $sim, $factory, $opmap, $visited) {
        die "GAP: memory-reading loop condition not yet lowered\n"
            if _cond_reads_memory($cond_start);
        # Which pad slots does the CONDITION mutate? These run once more than the
        # body (the failing N+1th eval), so post-loop they read their Phi back-edge
        # (the value after that failing pass), not the header Phi (see Phase 4b).
        my $cond_mutated = _scout_condition_mutated_targs($cv, $cond_start, $sim, $opmap);

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

        # A body element store advances memory; seed a header memory-Phi from the
        # pre-loop memory so the body's store advances OFF the Phi and the
        # post-loop read (which the loop may reach with zero iterations) observes
        # init OR back-edge. Memory has no scalar stamp, so this is a plain Phi
        # (no _make_loop_phi stamp copy, no _patch_loop_phi stamp join).
        my $mem_phi;
        if (_body_stores_memory($cond_start)) {
            $mem_phi = $factory->make_unique('Phi',
                inputs => [$sim->memory], region => $loop_node);
            $sim->set_memory($mem_phi);
        }

        # Phase 3: the real walk (condition + body against the Phi bindings).
        # $break_projs collects a mid-body `last if C` exit edge (Proj + the
        # bindings at the break point) so Phase 5 can add it as an extra
        # predecessor of the loop's exit Region.
        my @break_projs;
        my $exit_proj = _walk_loop_body($cv, $cond_start, $sim, $factory,
            $opmap, {}, $visited, $loop_node, \@break_projs);
        die "GAP: loop without a lowerable condition\n"
            unless defined $exit_proj;

        # Phase 4: patch back-edges and stamps.
        my $post_scope = $sim->scope_bindings;
        # The body walk rebound each mutated slot to its last in-loop value -- the
        # Phi back-edge. Capture it BEFORE _patch_loop_phi re-points the slot at the
        # Phi, so Phase 4b can restore a condition-mutated slot to it (the AT-EXIT
        # value) instead.
        my %backedge = map { $_ => $post_scope->{$_} } $mutated->@*;
        _patch_loop_phi($sim, $_, $phis{$_}, $post_scope->{$_}) for $mutated->@*;

        # Phase 4b: a CONDITION-mutated slot runs on the failing (N+1th) pass too,
        # so its post-loop value is the mutation's result on that pass -- the Phi
        # back-edge (`Subtract($i_phi, 1)`, reading the header Phi's EXIT value),
        # NOT the header Phi itself (which holds the value that FAILED the test).
        # _patch_loop_phi just re-pointed the slot at the Phi; override it back to
        # the back-edge. The backend recognizes such a back-edge (it gains a
        # post-loop consumer beyond its own Phi) and lowers it in the loop header,
        # where it dominates the exit. A BODY-mutated slot keeps the Phi (the body
        # does not run on the exit pass), so override only the condition's slots.
        for my $targ ($cond_mutated->@*) {
            next unless exists $backedge{$targ};
            $sim->define($targ, $backedge{$targ});
        }
        # Patch the memory-Phi's back-edge to the body's final store; then the
        # exit memory is the header Phi (init OR back-edge) so the post-loop read
        # takes it.
        if (defined $mem_phi) {
            $mem_phi->set_backedge($sim->memory);
            $sim->set_memory($mem_phi);
        }

        # Phase 5: post-loop control continues on the exit edge. A mid-body
        # `last` adds its guard-taken Proj as an extra predecessor of the exit
        # Region -- the loop now exits via the header-false edge OR the break.
        my @exit_preds = ($exit_proj, map { $_->{proj} } @break_projs);
        my $exit_region = $factory->make_cfg('Region', inputs => \@exit_preds);
        $loop_node->set_region($exit_region);
        $sim->set_control($exit_region);

        # SOUNDNESS for a mid-body break: the exit reads header Phis, correct for
        # the header-false path. On the break path a slot rebound BEFORE the break
        # holds a DIFFERENT value (its break-point binding) than its header Phi. If
        # such a slot is read post-loop, the two exit paths disagree and need an
        # exit Phi -- which the backend lowers only when it is DEAD (dropped) and
        # refuses loudly when it is LIVE (a real multi-exit value merge). Bind each
        # differing slot to an exit Phi over [header-Phi, break-binding]; DCE drops
        # it when the slot is dead post-loop (the common `last` that only breaks),
        # and a live read turns it into a loud GAP rather than a miscompile.
        for my $brk (@break_projs) {
            my $brk_bindings = $brk->{bindings};
            for my $targ (sort _scope_key_order keys %$brk_bindings) {
                my $header = $sim->scope_bindings->{$targ};   # header Phi (patched)
                my $bval   = $brk_bindings->{$targ};
                next unless defined $header && defined $bval && $header != $bval;
                my $exit_phi = $factory->make('Phi',
                    inputs => [$header, $bval],
                    region => $exit_region,
                    (defined $header->stamp ? (stamp => $header->stamp) : ()));
                $sim->define($targ, $exit_phi);
            }
        }
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
        # NumGt(high+1, i_phi) per the corpus D3 ir-block. The backend recovers
        # it as the comparison consuming a header Phi; it needs no consumer here.
        # A CONSTANT high folds high+1 at compile time (preserves the D3 golden
        # shape); a RUNTIME high (`for my $i (0..$n)` / `(0..$#a)`) emits an
        # Add(high, 1) so the bound is computed at run time. A const high+1 at
        # IV_MAX overflows to an NV and wraps in the emitted i64 (zero iterations,
        # silently) -- refuse that edge.
        my $bound;
        if ($high->isa('SoN::IR::Node::Constant')
                && ($high->const_type // '') eq 'integer') {
            die "GAP: foreach range bound at IV_MAX not yet lowered\n"
                if $high->value >= 9223372036854775807;
            $bound = $factory->make('Constant',
                value      => $high->value + 1,
                const_type => 'integer',
                stamp      => SoN::IR::Stamp->new(type => 'Int'));
        }
        else {
            # Runtime high bound: NumGt(Add(high, 1), i_phi). The +1 preserves the
            # inclusive-range contract (loop while i <= high).
            my $one = $factory->make('Constant',
                value => 1, const_type => 'integer',
                stamp => SoN::IR::Stamp->new(type => 'Int'));
            $bound = $factory->make('Add',
                inputs => [$high, $one],
                stamp  => SoN::IR::Stamp->new(type => 'Int'));
        }
        my $range_cond = $factory->make('NumGt',
            inputs => [$bound, $i_phi],
            stamp  => SoN::IR::Stamp->new(type => 'Boolean'));
        # Structural control edge to the Loop (see _walk_loop_body), so the
        # backend recovers this continuation test unambiguously.
        $range_cond->set_control_in($loop_node);

        # A body element store advances memory; seed a header memory-Phi from the
        # pre-loop memory (memory analog of the carried-slot Phi; no stamp).
        my $mem_phi;
        if (_body_stores_memory($body_start)) {
            $mem_phi = $factory->make_unique('Phi',
                inputs => [$sim->memory], region => $loop_node);
            $sim->set_memory($mem_phi);
        }

        # A foreach has no and/or loop condition (the range iterator drives it,
        # and its own iteration `and` was consumed at $and_op above). So any
        # top-level and/or in the body is a postfix MODIFIER guard (`STMT unless
        # C`). _walk_loop_body's condition handler would treat that modifier as the
        # loop condition, drop the guard's If, and fire the guarded statement every
        # iteration (silent miscompile: `$s=$s+$i unless $i==2` over 1..3 gave 106
        # not 104, zhi 019f5a27). Lowering a nested guard inside a loop body is a
        # control-flow feature not yet built; GAP loudly before the real walk.
        die "GAP: nested and/or (postfix modifier) inside a foreach body not yet"
          . " lowered\n"
            if _body_has_modifier_andor($body_start);

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
        if (defined $mem_phi) {
            $mem_phi->set_backedge($sim->memory);
            $sim->set_memory($mem_phi);
        }

        # Phase 5: post-loop control continues on the exit edge.
        my $exit_region = $factory->make_cfg('Region', inputs => [$exit_proj]);
        $loop_node->set_region($exit_region);
        $sim->set_control($exit_region);
        return;
    }

    # Translate an array foreach (`for my $x (@a)` -- enteriter with OPf_STACKED
    # over a single aggregate) to a counted loop over the array's elements. The
    # skeleton mirrors _translate_foreach_range (Loop/Phi/Proj/Region, the same
    # while-loop shape the backend already lowers), but the induction is
    # 0..len-1 and the iterator variable binds to Subscript(arr, i) each pass,
    # not to the induction value itself. for/foreach are aliases (same optree),
    # so both spellings reach here. zhi 019f5da9.
    sub _translate_foreach_array ($cv, $enteriter, $sim, $factory, $opmap, $visited, $array) {
        my $x_targ = $enteriter->targ;

        # Locate the body (enteriter->next: unstack, iter, then the and whose
        # other-branch is the body) -- identical structure to the range form.
        my $it = $enteriter->next;
        $it = $it->next while $$it && $it->name ne 'iter';
        die "GAP: foreach without an iter op\n" unless $$it;
        my $and_op = $it->next;
        die "GAP: foreach without an and condition\n"
            unless $$and_op && $and_op->name eq 'and';
        my $body_start = $and_op->other;

        # A nested postfix modifier (`STMT if C`) in the body is an unbuilt
        # control-flow feature; the same GAP the range form refuses (zhi 019f5a27).
        die "GAP: nested and/or (postfix modifier) inside a foreach body not yet"
          . " lowered\n"
            if _body_has_modifier_andor($body_start);

        # ALIASING: Perl's `for my $x (@a)` ALIASES $x to each element, so a body
        # write `$x = ...` MUTATES @a in place. This lowering binds $x to a
        # READ-ONLY Subscript(arr, i) element copy, so a write to $x would NOT
        # propagate back to @a -- a silent miscompile (`for my $x (@a){ $x=$x+1 }
        # $a[0]` would read the un-incremented element). Detect an iterator write
        # by scouting WITHOUT excluding $x_targ: if $x is in the mutated set, the
        # body assigns the alias. GAP loudly until the write-back is modeled.
        die "GAP: foreach body writes the iterator variable (aliasing write-back "
          . "to the array) not yet lowered\n"
            if _body_writes_targ($cv, $body_start, $sim, $opmap, $x_targ);

        # The loop bound is the array's element count.
        my $len = $factory->make('Length',
            inputs => [$array],
            stamp  => SoN::IR::Stamp->new(type => 'Int'));
        my $zero = $factory->make('Constant',
            value => 0, const_type => 'integer',
            stamp => SoN::IR::Stamp->new(type => 'Int'));
        my $elem_stamp = _array_element_stamp($array);

        # Phase 1: scout the body. $x rides on enteriter (its own slot) and gets
        # the element binding, not a carried-value Phi, so exclude it.
        my $pre_scope = $sim->scope_bindings;
        my $mutated = _scout_mutated_targs($cv, $body_start, $sim, $opmap, [$x_targ]);

        # Phase 2: header -- induction Phi (i: 0..len-1) plus one Phi per mutated
        # slot. The induction Phi is NOT bound to $x; $x is the element read below.
        my $loop_node = $factory->make_cfg('Loop', inputs => [$sim->control]);
        $sim->set_control($loop_node);
        my $i_phi = _make_loop_phi($factory, $loop_node, $zero);
        my %phis;
        for my $targ ($mutated->@*) {
            my $phi = _make_loop_phi($factory, $loop_node, $pre_scope->{$targ});
            $phis{$targ} = $phi;
            $sim->define($targ, $phi);
        }

        # Continuation: loop while i < len, authored as NumGt(len, i_phi) -- the
        # same shape the backend recovers as "the comparison consuming a header
        # Phi" (structural loop_control edge to the Loop).
        my $range_cond = $factory->make('NumGt',
            inputs => [$len, $i_phi],
            stamp  => SoN::IR::Stamp->new(type => 'Boolean'));
        $range_cond->set_control_in($loop_node);

        # A body element store advances memory; seed a header memory-Phi from the
        # pre-loop memory (same as the range form).
        my $mem_phi;
        if (_body_stores_memory($body_start)) {
            $mem_phi = $factory->make_unique('Phi',
                inputs => [$sim->memory], region => $loop_node);
            $sim->set_memory($mem_phi);
        }

        # Phase 3: body under Proj(loop,0); exit on Proj(loop,1). Bind $x to the
        # element read Subscript(arr, i_phi, memory) BEFORE walking the body, so a
        # body reference to $x reads element[i].
        my $body_proj = $factory->make_cfg('Proj', inputs => [$loop_node], index => 0);
        my $exit_proj = $factory->make_cfg('Proj', inputs => [$loop_node], index => 1);
        $sim->set_control($body_proj);
        my $elem = $factory->make('Subscript',
            inputs => [$array, $i_phi, $sim->memory],
            (defined $elem_stamp ? (stamp => $elem_stamp) : ()));
        $sim->define($x_targ, $elem);
        _walk_loop_body($cv, $body_start, $sim, $factory, $opmap, {}, $visited);

        # Phase 4: back-edges. The induction step is +1; carried slots patch like
        # the while loop.
        my $one = $factory->make('Constant',
            value => 1, const_type => 'integer',
            stamp => SoN::IR::Stamp->new(type => 'Int'));
        my $i_next = $factory->make('Add',
            inputs => [$i_phi, $one],
            stamp  => _result_stamp('Add', [$i_phi, $one]));
        $i_phi->set_backedge($i_next);
        my $post_scope = $sim->scope_bindings;
        _patch_loop_phi($sim, $_, $phis{$_}, $post_scope->{$_}) for $mutated->@*;
        if (defined $mem_phi) {
            $mem_phi->set_backedge($sim->memory);
            $sim->set_memory($mem_phi);
        }

        # Phase 5: post-loop control continues on the exit edge.
        my $exit_region = $factory->make_cfg('Region', inputs => [$exit_proj]);
        $loop_node->set_region($exit_region);
        $sim->set_control($exit_region);
        return;
    }

    # Walk a loop's condition + body ops. With $loop_node (the real walk of
    # _translate_while_loop) the condition builds Projs directly on the Loop
    # per the corpus contract and the exit Proj is returned; without it (the
    # scout walk, whose nodes are throwaway) the legacy If shape is kept --
    # the binding effects are identical either way, which is all the scout
    # measures.
    sub _walk_loop_body ($cv, $op, $sim, $factory, $opmap, $loop_visited, $outer_visited, $loop_node = undef, $break_projs = undef) {
        my $ctx = { mode => 'loop' };
        my $exit_proj;
        my $condition_fired = 0;
        # A do-block (`$x = do { STMT; ...; RESULT }`) opens an `enter`/`leave`
        # sub-statement scope INSIDE the enclosing expression. Its intermediate
        # statements (`my $t=$i;`) are void: padsv_store pushes the stored value,
        # which perl discards at the do-block's inner statement boundary. The
        # StackSim does not model that reset (nextstate is a SKIP), so the leaked
        # value corrupts a later pop -- the accumulator's `$s = $s + ...` add read
        # $i's leftover instead of $s (zhi 019f59b1). Track the stack depth at each
        # `enter` and, at a `nextstate` inside the do-block, pop leftovers back to
        # that depth -- preserving the OUTER operand ($s) pushed before the enter.
        my @enter_depth;
        # Count top-level body statement boundaries (nextstate outside a do-block).
        # A `last if COND` is hoistable into the loop header ONLY when it is the
        # FIRST body statement (stmt_count == 1: just its own opening nextstate has
        # passed) -- otherwise hoisting the exit check to the top would reorder it
        # ahead of the statements that ran before it in the source (a miscompile).
        my $stmt_count = 0;
        while ($$op) {
            # Stop if we've looped back (unstack goes back to condition)
            last if $loop_visited->{$$op}++;

            my $name = $op->name;

            if ($name eq 'enter') {
                push @enter_depth, $sim->stack_depth;
            }
            elsif ($name eq 'leave') {
                pop @enter_depth;
            }
            elsif ($name eq 'nextstate' && @enter_depth) {
                # A statement boundary inside a do-block: discard the just-completed
                # sub-statement's leftover values, keeping the do-block entry depth.
                my $base = $enter_depth[-1];
                $sim->pop_node while $sim->stack_depth > $base;
            }
            elsif ($name eq 'nextstate') {
                $stmt_count++;
            }

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

            # A bare `last`/`next` op reached directly (not via an `and(other->..)`
            # guard) is an UNCONDITIONAL loop control -- walking past one produced
            # silently wrong graphs (a dropped `last` ran the loop to completion).
            # The conditional `X if C` forms are caught at the `and` handlers
            # below; only the unconditional (or `redo`) forms reach here.
            if ($name eq 'last' || $name eq 'next' || $name eq 'redo') {
                die "GAP: loop control ($name) inside a loop body not yet lowered\n";
            }

            # A ternary (cond_expr) in the loop body is a VALUE-producing select
            # (`$s += ($i > 1 ? 10 : 1)`) -- delegate to the shared
            # _handle_cond_expr, which builds the same TernaryExpr / If+Proj+Region
            # construction the main walk uses. Its arm walk marks its ops visited
            # in $loop_visited so this loop does not re-walk them. Requires a value
            # on the stack (the cond op has been walked and pushed the condition);
            # a void statement-level cond_expr is not this shape and falls through
            # to the branch-GAP below.
            if ($name eq 'cond_expr' && $opmap->is_branch($name)
                && $sim->stack_depth > 0) {
                $loop_visited->{$$op}++;
                $op = _handle_cond_expr($cv, $op, $sim, $factory, $opmap,
                    $loop_visited);
                next;
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

            # `last if COND` at the head of a headless `while(1)` body: the `and`
            # whose ->other is a `last` op is a conditional break. The loop has no
            # written header condition (the `1` folded away), so this exit test IS
            # the loop's continuation, negated: run while NOT COND. Hoist it exactly
            # like a written header -- wire the negated comparison to the Loop and
            # continue the body walk on the false (continue) arm (and->next), NOT
            # the true arm (and->other = last). A comparison-only guard is handled;
            # a bare-truthiness `last if $flag` (no icmp to negate) still GAPs.
            # Fires in scout mode too (loop_node undef): the scout must skip the
            # `last` guard and walk the continue arm to find the body's mutated
            # slots -- it just does no control wiring.
            if ($name eq 'and' && $sim->stack_depth > 0
                    && $op->can('other') && ${$op->other}
                    && $op->other->name eq 'last'
                    && $stmt_count == 1) {
                # HEAD-of-body `last if`: nothing in the iteration ran before the
                # exit check, so it hoists soundly into the loop's continuation
                # (negated). A `last if` deeper in the body is handled by the
                # mid-body loop-control handler below (a real If split), not here.
                die "GAP: last inside a loop body already has a loop condition\n"
                    if $condition_fired++;
                my $cond = $sim->pop_node;
                if (defined $loop_node) {
                    my $neg = _negate_comparison($cond, $factory)
                        or die "GAP: non-comparison `last if` guard inside a loop"
                             . " body not yet lowered\n";
                    $neg->set_control_in($loop_node);
                    my $body_proj = $factory->make_cfg('Proj',
                        inputs => [$loop_node], index => 0);
                    $exit_proj = $factory->make_cfg('Proj',
                        inputs => [$loop_node], index => 1);
                    $sim->set_control($body_proj);
                }
                # Continue on the false arm -- the rest of the body runs when the
                # `last` guard is NOT taken.
                $op = $op->next;
                next;
            }

            # MID-BODY `last if C` / `next if C`: an `and` whose ->other is a
            # `last`/`next` op that is NOT at the head of the body (statements ran
            # before it). This is a genuine mid-loop control split: build a real
            # `If(C)` at this position and route the guard-taken arm accordingly.
            #
            #   `next if C` = `if (!C) { REST-OF-BODY }`: `next` skips the rest of
            #     the body this pass, then the back-edge runs unchanged. The
            #     guard-taken (C true) arm is EMPTY (skip to the merge/back-edge);
            #     the guard-not-taken (C false) arm runs the rest of the body.
            #     merge() Regions the two arms and Phis any slot the rest rebinds
            #     -- no loop-control edge is needed (a `next` is a guard on the
            #     remainder, not a control transfer).
            #
            #   `last if C`: `last` LEAVES the loop when C is true -- a real second
            #     exit edge. The guard-taken (C true) arm routes to the loop's exit
            #     Region (its Proj becomes an extra predecessor via $break_projs);
            #     the guard-not-taken (C false) arm continues the rest of the body
            #     to the back-edge. Sound only when every post-loop-read slot holds
            #     its header Phi at the break point (the exit reads header Phis);
            #     a slot rebound BEFORE the break and read post-loop is the
            #     multi-exit merge case and GAPs loudly (below).
            if ($name eq 'and' && $sim->stack_depth > 0
                    && $op->can('other') && ${$op->other}
                    && ($op->other->name eq 'last' || $op->other->name eq 'next')) {
                my $kind = $op->other->name;   # 'last' or 'next'
                # NOTE: a fired loop header condition ($condition_fired) is
                # EXPECTED here -- a `while (COND) { ...; last if C; ... }` has
                # both. The mid-body break is an independent If split, not a
                # second loop condition, so it does not conflict.
                my $cond = $sim->pop_node;
                # The guard op's op_next is where the rest-of-body arm converges
                # back (its first op). Build the If and split the control.
                my $if_node = $factory->make_cfg('If',
                    inputs => [$sim->control, $cond]);
                # Proj 0 = then (C true = guard taken), Proj 1 = else (C false =
                # guard not taken = run the rest).
                my $taken_proj = $factory->make_cfg('Proj',
                    inputs => [$if_node], index => 0);
                my $rest_proj  = $factory->make_cfg('Proj',
                    inputs => [$if_node], index => 1);

                # Walk the REST of the body (op->next chain) on the guard-not-taken
                # arm. Use a snapshot so the guard-taken (skip/exit) arm keeps the
                # pre-guard bindings. _walk_branch stops at the body's unstack (an
                # unhandled op) or a visited op.
                my $rest_sim = $sim->snapshot;
                $rest_sim->set_control($rest_proj);
                my ($rest_end) =
                    _walk_branch($cv, $op->next, $rest_sim, $factory, $opmap,
                        $loop_visited);
                # Drain any leftover residual the rest-arm pushed (a void
                # statement value) so merge() does not build a spurious stack Phi.
                $rest_sim->pop_node while $rest_sim->stack_depth > $sim->stack_depth;

                if ($kind eq 'next') {
                    # The guard-taken arm (C true) skips the rest: it holds only
                    # $taken_proj control with the pre-guard bindings. Merge the
                    # skip arm (self, Proj 0) with the rest arm (Proj 1) so the
                    # merge Phi's arm 0 = skip (pre-guard) and arm 1 = rest.
                    my $skip_sim = $sim->snapshot;
                    $skip_sim->set_control($taken_proj);
                    my $pre = $sim->scope_bindings;
                    $skip_sim->merge($rest_sim, $factory, $if_node);
                    # Adopt the merged control / memory / scope into the main sim.
                    # A merge Phi over a loop-carried accumulator becomes that
                    # slot's back-edge; _patch_loop_phi rejects an UNSTAMPED
                    # back-edge, so stamp each newly-built merge Phi from the join
                    # of its (stamped) arm values -- the same input-join stamping
                    # _make_ternary applies to a select.
                    my $merged = $skip_sim->scope_bindings;
                    for my $targ (keys %$merged) {
                        my $m = $merged->{$targ};
                        next unless defined $m
                            && $pre->{$targ} && $m != $pre->{$targ}
                            && $m->operation eq 'Phi' && !defined $m->stamp;
                        my ($a, $b) = $m->inputs->@*;
                        $m->set_stamp(SoN::IR::Stamp::join($a->stamp, $b->stamp))
                            if defined $a && defined $b
                            && defined $a->stamp && defined $b->stamp;
                    }
                    $sim->set_control($skip_sim->control);
                    $sim->set_memory($skip_sim->memory);
                    $sim->define($_, $merged->{$_}) for keys %$merged;
                }
                else {
                    # `last`: the guard-taken arm LEAVES the loop. Its Proj is an
                    # extra predecessor of the loop's exit Region ($break_projs,
                    # threaded to the caller which wires the exit Region + runs the
                    # soundness check). In scout mode ($break_projs undef) the
                    # break edge is not wired -- the scout only measures the rest
                    # arm's rebinds, so record nothing and continue.
                    push @$break_projs,
                        { proj => $taken_proj, bindings => $sim->scope_bindings }
                        if defined $break_projs;
                    # Continue the main walk on the rest arm's merged state.
                    $sim->set_control($rest_sim->control);
                    $sim->set_memory($rest_sim->memory);
                    my $rest_scope = $rest_sim->scope_bindings;
                    $sim->define($_, $rest_scope->{$_}) for keys %$rest_scope;
                }

                # Resume the outer walk at the op the rest-arm converged on (the
                # body's unstack / leaveloop) so the loop-body loop terminates.
                $op = (defined $rest_end && ref $rest_end) ? $rest_end : $op->next;
                next;
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
                    # Wire the condition's control edge to the Loop so the
                    # backend recovers it structurally (its control_in IS the
                    # Loop) rather than by the ambiguous "first icmp consuming a
                    # header Phi" heuristic, which a body comparison can hijack.
                    # An `or` condition (until) would need the negated sense.
                    die "GAP: until (or-condition) loop not yet lowered\n"
                        if $name eq 'or';
                    # A bare-truthiness header (`while ($n)`) pops a non-comparison
                    # condition (the loop-carried value). The backend's structural
                    # recovery only accepts an icmp, so synthesize an explicit
                    # NumNe($cond, 0) truthiness test and wire the control edge onto
                    # THAT -- otherwise the backend falls back to a body comparison.
                    $cond = _truthiness_test($cond, $factory)
                        unless _is_comparison($cond);
                    $cond->set_control_in($loop_node);
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

    # Does a foreach body (op chain from $body_start to its loop terminator)
    # contain a top-level `and`/`or` postfix modifier guard the loop-body walker
    # cannot lower? A foreach has no and/or loop condition, so an `and`/`or` here
    # is either a `STMT if/unless C` value modifier (unlowered, zhi 019f5a27) OR a
    # loop-control guard `last if C` / `next if C` whose ->other is a last/next op
    # -- and THAT the loop-body walker DOES lower (mid-body If split). Flag only
    # the former. Pure lexical scan; stop at the body's unstack/leaveloop (the
    # iteration/loop boundary) so a following loop's ops are not scanned.
    sub _body_has_modifier_andor ($body_start) {
        my %seen;
        for (my $op = $body_start; $$op && !$seen{$$op}; $op = $op->next) {
            $seen{$$op} = 1;
            my $name = $op->name;
            last if $name eq 'unstack' || $name eq 'leaveloop';
            if ($name eq 'and' || $name eq 'or') {
                # A loop-control guard (`last if`/`next if`) is lowered by
                # _walk_loop_body's mid-body handler; it is not an unlowered
                # modifier.
                my $other = $op->can('other') && ${$op->other}
                    ? $op->other->name : '';
                next if $other eq 'last' || $other eq 'next';
                return 1;
            }
        }
        return 0;
    }

    # The arm scans below bound their walk by comparing an op ADDRESS
    # (`$$op != $stop`), but every caller has a B::OP object in hand and it is
    # one `$$` away from being right. Passing the object silently disables the
    # bound -- a ref numifies to its SV address, which never equals an op
    # address -- so the scan runs past the arm to the end of the sub and reports
    # effects belonging to LATER statements. Normalising here rather than at the
    # call sites means a caller cannot get it wrong: accept either form.
    sub _op_addr ($stop) {
        return undef unless defined $stop;
        return ref($stop) ? $$stop : $stop;
    }

    # Does the arm (op chain from $start up to but excluding $stop) contain an
    # ELEMENT STORE -- an sassign whose lvalue is an aelem/helem, OR the fused
    # aelemfastlex_store the optimizer emits for a constant-index lexical-array
    # element assignment (`$a[0] = 9`)? Such a store advances memory (memory-
    # SSA), so the branch must be built with a control-dependent store + a
    # memory-Phi (2b), not a straight-line merge. Pure lexical scan (no
    # translation, no side effects); OPf_MOD (lvalue, flag 0x20) on the
    # aelem/helem distinguishes a store target from a read, while the fused
    # *_store op is unconditionally a store (its `_store` suffix IS the lvalue).
    # _stash_target_sigil($aassign_op) -> '@' | '%' | undef
    #
    # Which container an `our @x = ...` / `our %h = ...` assigns into. A
    # The aassign TARGET's sigil is not on the node the LHS pushed (that node
    # is built by the read site, which stamps its own), so it comes
    # from the op that pushed the target: rv2av for an array, rv2hv for a hash.
    # Walk the aassign's subtree for the first of either.
    sub _stash_target_sigil ($aassign) {
        my @queue = ($aassign);
        my %seen;
        while (my $op = shift @queue) {
            next unless $op && ref($op) && $$op && !$seen{$$op}++;
            my $n = $op->name;
            return '@' if $n eq 'rv2av';
            return '%' if $n eq 'rv2hv';
            next unless $op->can('first') && ${ $op->first };
            for (my $kid = $op->first; $kid && $$kid; $kid = $kid->sibling) {
                push @queue, $kid;
            }
        }
        return undef;
    }

    sub _arm_has_element_store ($start, $stop) {
        $stop = _op_addr($stop);
        my %seen;
        for (my $op = $start; $$op && $$op != $stop && !$seen{$$op}; $op = $op->next) {
            $seen{$$op} = 1;
            my $name = $op->name;
            return 1 if $name eq 'aelemfastlex_store'
                     || $name eq 'helemfastlex_store';
            next unless $name eq 'aelem' || $name eq 'helem';
            return 1 if $op->flags & 0x20;   # OPf_MOD -- an lvalue element target
        }
        return 0;
    }

    # Does the arm (op chain from $start up to but excluding $stop) STORE to a
    # class FIELD? A branched field mutation (`method bump { if(C){$n=$n+5}
    # else{$n=$n+1} }`) must build real control flow so each arm's field store is
    # control-dependent on its own Proj and a Region merges the arms -- exactly
    # like an element store. Without this the arm falls to the pad-rebind merge,
    # which merges only pad SCOPE bindings (a field is not one), so the store is
    # never emitted control-guarded and the method body reaches the backend with
    # no repr (zhi 019f5368). A field write is a TARGMY op (OPpTARGET_MY) or a
    # padsv_store whose targ's padname is_field.
    sub _arm_has_field_store ($cv, $start, $stop) {
        $stop = _op_addr($stop);
        my $padlist = $cv->PADLIST;   # loop-invariant; the padname table is per-CV
        return 0 unless $$padlist;
        my $padnames = $padlist->ARRAYelt(0);
        my %seen;
        for (my $op = $start; $$op && $$op != $stop && !$seen{$$op}; $op = $op->next) {
            $seen{$$op} = 1;
            my $is_targmy   = $op->can('targ') && $op->targ && ($op->private & 16);
            my $is_padstore = $op->name eq 'padsv_store' && $op->can('targ') && $op->targ;
            next unless $is_targmy || $is_padstore;
            my $pn = $padnames->ARRAYelt($op->targ);
            return 1 if ref $pn eq 'B::PADNAME' && SoN::FieldInfo::is_field($pn);
        }
        return 0;
    }

    # Does the arm (op chain from $start up to but excluding $stop) contain a
    # VOID METHOD CALL -- a `$c->inc`-style dispatch whose result is discarded?
    # Such a call carries a side effect (a field mutation inside the method), so
    # the branch must build real control flow (If + Proj + merge) exactly like an
    # element store: the call is walked on Proj(true), control-threaded, and a
    # Region merges the arms so a later read sees it. Without this the void call
    # falls to the pad-rebind value-merge path, which merges nothing (a void call
    # rebinds no pad slot) and silently drops the effect (zhi 019f2df7).
    #
    # A void method call is a method_named followed by an entersub in VOID want
    # (OPf_WANT_VOID). The linear ->next scan follows THIS arm only; a nested
    # branch (and/or/cond_expr) inside the arm is NOT a simple void-call arm --
    # stop at it so a nested branch stays the loud GAP the convergence check
    # raises, rather than being routed through the $mem_branch merge with a
    # broken memory state.
    # $join (optional): the address where the two arms rejoin (op AFTER the
    # construct). A single-op arm's ->next chain runs straight THROUGH the join
    # into the following statement -- e.g. `print $c ? "y" : "n"`, where the
    # false arm `const "n"` ->next IS the `print` (the join, a void op past the
    # arm). Without a join bound the scan mistakes that trailing print for an
    # in-arm void call and routes a plain single-value select down the void
    # control-flow path. Stop at the join so only ops genuinely inside the arm
    # are considered.
    sub _arm_has_void_call ($start, $stop, $join = undef) {
        ($stop, $join) = (_op_addr($stop), _op_addr($join));
        # ONE seen-set for the whole scan, shared across the nested-branch
        # descent below. A per-call set would let two branches that can reach
        # each other recurse forever -- measured as "Deep recursion on
        # _arm_has_die" and then a Killed process on t/b-son-backend.t, whose
        # deeply-branched real-world code is what exposed it.
        return _arm_has_void_call_from($start, $stop, $join, {});
    }

    sub _arm_has_void_call_from ($start, $stop, $join, $seen) {
        for (my $op = $start;
             $$op && $$op != $stop && !(defined $join && $$op == $join)
                 && !$seen->{$$op};
             $op = $op->next) {
            $seen->{$$op} = 1;
            my $name = $op->name;
            # A NESTED BRANCH. Its guarded body is reached via ->other, not
            # ->next, so the linear scan would walk straight past it and miss an
            # effect living inside. That effect still makes THIS arm one that
            # needs real control flow -- the arm cannot use the value-only merge
            # if anything under it must be control-pinned -- so descend into the
            # nested body and report what it finds.
            #
            # This asks only "does this arm need control flow?", which is
            # answered the same way no matter which side of the inner branch the
            # effect sits on. It does NOT attribute the effect to an arm; the
            # inner branch's own handler does that when it builds its own
            # If/Projs. Returning 0 here instead left the OUTER branch on the
            # pad-rebind path while the inner one built control flow beneath it,
            # so the inner guard was swallowed and its effect fired
            # unconditionally (measured: `if(C){if(C){print}}` printed nothing,
            # and a nested `die` exited 0 where perl exited 255).
            if ($name eq 'and' || $name eq 'or' || $name eq 'cond_expr') {
                return 1
                    if _arm_has_void_call_from($op->other, $stop, $join, $seen);
                next;
            }
            # A print is a statement effect in ANY context -- _handle_print
            # control-pins it, advancing the arm's control to the Print, so merge()
            # Regions it onto the taken arm. Even in SCALAR context (WANT=2, the
            # last-statement `if(C){print..}else{print..}` whose Bool return is the
            # sub's value), the print's stdout SIDE EFFECT must be guarded by the
            # branch -- otherwise both arms' prints land unconditionally on the
            # shared control and BOTH fire (a silent miscompile). Treat a print in
            # any context as a control-flow-requiring effect arm; its Bool return
            # value becomes the arm's residual for the value merge. (t/base/if.t,
            # t/base/cond.t last-statement if/else.)
            # `say` is desugared to the same Print node, so it is the same
            # statement effect and must be recognised here too -- otherwise a
            # `say` in an if/else arm lands unguarded on the shared control and
            # BOTH arms fire, the exact miscompile this line exists to stop.
            return 1 if $name eq 'print' || $name eq 'say';
            # A void entersub is the effect -- a method call (method_named
            # recorded the name earlier) OR a bare direct call (`helper()`);
            # both thread through _handle_entersub. OPf_WANT_VOID marks the
            # statement-effect call whose result is discarded.
            next unless $name eq 'entersub';
            return 1 if ($op->flags & 3) == 1;   # OPf_WANT_VOID
        }
        return 0;
    }

    # Does this arm `die`? A die is an abort -- a control exit that does NOT
    # rejoin the merge. Detected structurally (like _arm_has_void_call) so the
    # branch routes through the shared control-flow build: the die arm walks on
    # its own Proj, the walker creates an Unwind on that Proj (the arm's new
    # control), and merge() Regions the LIVE arm's control with the Unwind. The
    # backend lowers the Unwind to exit(255)+unreachable, so the merge's die
    # predecessor is dead and the live arm's value dominates. The $join bound
    # (as the arm-scan helpers use) stops the scan at the rejoin op.
    # Does this arm contain a void CALL (entersub)? A narrower question than
    # _arm_has_void_call, which also answers true for a print/say. The two
    # differ in where the effect can be PLACED: a Print pins once on its
    # control, while a Call is both a value and an effect and can be emitted
    # per-consumer. Callers that can pin the first but not the second ask this
    # separately. Descends into a nested branch for the same reason the others
    # do, sharing one seen-set.
    sub _arm_has_direct_call ($start, $stop, $join = undef) {
        ($stop, $join) = (_op_addr($stop), _op_addr($join));
        return _arm_has_direct_call_from($start, $stop, $join, {});
    }

    sub _arm_has_direct_call_from ($start, $stop, $join, $seen) {
        for (my $op = $start;
             $$op && $$op != $stop && !(defined $join && $$op == $join)
                 && !$seen->{$$op};
             $op = $op->next) {
            $seen->{$$op} = 1;
            my $name = $op->name;
            if ($name eq 'and' || $name eq 'or' || $name eq 'cond_expr') {
                return 1
                    if _arm_has_direct_call_from($op->other, $stop, $join, $seen);
                next;
            }
            next unless $name eq 'entersub';
            return 1 if ($op->flags & 3) == 1;   # OPf_WANT_VOID
        }
        return 0;
    }

    sub _arm_has_die ($start, $stop, $join = undef) {
        ($stop, $join) = (_op_addr($stop), _op_addr($join));
        # One shared seen-set across the nested descent -- see the note in
        # _arm_has_void_call.
        return _arm_has_die_from($start, $stop, $join, {});
    }

    sub _arm_has_die_from ($start, $stop, $join, $seen) {
        for (my $op = $start;
             $$op && $$op != $stop && !(defined $join && $$op == $join)
                 && !$seen->{$$op};
             $op = $op->next) {
            $seen->{$$op} = 1;
            my $name = $op->name;
            # A NESTED BRANCH: descend into its guarded body (reached via
            # ->other, which the linear ->next scan walks past). A die under a
            # nested branch still makes THIS arm need real control flow. See the
            # matching comment in _arm_has_void_call.
            if ($name eq 'and' || $name eq 'or' || $name eq 'cond_expr') {
                return 1
                    if _arm_has_die_from($op->other, $stop, $join, $seen);
                next;
            }
            # `exit` is the same CLASS as `die`: a control path that leaves and
            # does not rejoin the merge. It differs only in the status it sets,
            # which is the backend's business, not this scan's.
            return 1 if $name eq 'die' || $name eq 'exit';
        }
        return 0;
    }

    # Does a loop body contain an ELEMENT STORE? A body store advances memory,
    # so the loop needs a header memory-Phi (2b-4) exactly like a loop-carried
    # scope slot. The condition head's ->next chain runs condition ops up to the
    # and/or that closes it; the BODY hangs off that and/or's ->other branch (the
    # while condition short-circuits AROUND the body), so descend there -- the
    # foreach caller passes body_start directly (no and/or to cross). Same
    # OPf_MOD lvalue test as _arm_has_element_store; the cycle guard bounds it.
    sub _body_stores_memory ($start) {
        my %seen;
        for (my $op = $start; $$op && !$seen{$$op}; $op = $op->next) {
            $seen{$$op} = 1;
            my $name = $op->name;
            last if $name eq 'unstack' || $name eq 'leaveloop';
            # shift/pop MUTATE their array (a memory effect), so a loop whose
            # condition or body drains an array carries memory through the header.
            return 1 if $name eq 'shift' || $name eq 'pop';
            if ($name eq 'and' || $name eq 'or') {
                return 1 if _cond_drains_array($start, $$op);
                return _body_stores_memory($op->other);
            }
            next unless $name eq 'aelem' || $name eq 'helem';
            return 1 if $op->flags & 0x20;   # OPf_MOD -- an lvalue element target
        }
        return 0;
    }

    # Does the CONDITION segment (from $start up to the closing and/or at
    # $stop_addr) contain a shift/pop array drain? The condition ops precede the
    # and/or; _body_stores_memory's and/or branch recurses into the BODY
    # (->other), so a drain in the condition itself (`while (shift @q)`) is only
    # seen by scanning the leading segment here.
    sub _cond_drains_array ($start, $stop_addr) {
        my %seen;
        for (my $op = $start; $$op && $$op != $stop_addr && !$seen{$$op}; $op = $op->next) {
            $seen{$$op} = 1;
            my $name = $op->name;
            return 1 if $name eq 'shift' || $name eq 'pop';
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
        # A LIST-context ternary (`print $c ? "y" : "n"`) whose arms each produce
        # exactly ONE value is the same select shape as a scalar-context ternary:
        # each arm pops one value and the TernaryExpr picks between them. The
        # plain scalar path below handles that. A genuine multi-element list arm
        # (`my @a = $c ? (1,2) : (3,4)`) would need per-arm value LISTS -- the
        # arm-value handling below detects an arm whose depth-delta != 1 and GAPs
        # loudly rather than silently dropping the extra values.
        my $list_ctx = ($op->flags & 3) == 3;   # OPf_WANT == OPf_WANT_LIST

        my $cond = $sim->pop_node;
        my $join_addr = _find_join_addr($op->other, $op->next) || undef;

        my $base_depth = $sim->stack_depth;
        my $walk_arm = sub ($start, $arm_control = undef) {
            my $arm_sim = $sim->snapshot;
            # Memory-SSA 2b-3: an element-store arm walks on its own guarded
            # Proj so the store is CONTROL-DEPENDENT on the branch (emitted only
            # in that arm) and its memory advance is per-arm. The scalar/value
            # path passes no control and keeps the snapshot's pre-branch control.
            $arm_sim->set_control($arm_control) if defined $arm_control;
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
            # The arm's value-count is its depth ABOVE the pre-branch base. A
            # scalar-context arm pushes exactly one; a list-context arm whose
            # source is a genuine multi-element list (`(1,2)`) pushes more --
            # detected by the caller so the single-value list case (the t/base
            # `print $c ? "y" : "n"` idiom, each arm a lone string) lowers while
            # the multi-value list still GAPs loudly.
            my $delta = $arm_sim->stack_depth - $base_depth;
            my $val = $delta > 0
                ? $arm_sim->pop_node
                : _undef_constant($factory);
            return ($val, $end, $arm_sim, $delta);
        };

        # Memory-SSA 2b-3: a flat if/else whose arm STORES to an element must
        # build real control flow -- each arm's store is control-dependent on
        # its own Proj(If) and the memory after the join is a memory-Phi over a
        # Region merging the two arms. Gated on an element-store arm (either
        # side) so the working scalar/value pad-rebind path is untouched. Build
        # the If + Proj(true, index 0) / Proj(false, index 1) BEFORE the arm
        # walks and route each arm onto its Proj.
        # An element store threads on MEMORY (needs a stack Phi in value context);
        # a field store (`if(C){$n=$n+5}else{$n=$n+1}`, $n a class field) threads
        # on CONTROL so its arm residual is a plain merged ternary. Both need the
        # same real control flow (If/Proj/Region) rather than the pad-rebind merge
        # (zhi 019f5368). Compute each flag once; $mem_branch drives the shared
        # control-flow path and $elem_branch alone gates the value-context GAP.
        # A VOID statement-effect arm (`if($c){print "a\n"}else{print "b\n"}`, a
        # void print or a void method call) is the same shape as the logical-op
        # arm the &&/|| handler routes through _arm_has_void_call: the effect
        # rebinds no pad slot, so the pad-rebind merge path below drops it. Build
        # the same real control flow so each arm's control-pinned effect fires on
        # its own Proj and a Region merges the arms. An `if` statement is always
        # void (WANT 0/1), so this contributes only to the void path.
        my $elem_branch = _arm_has_element_store($op->other, $op->next)   # true arm
                       || _arm_has_element_store($op->next, $op->other);  # false arm
        my $mem_branch  = $elem_branch
                       || _arm_has_field_store($cv, $op->other, $op->next)
                       || _arm_has_field_store($cv, $op->next, $op->other)
                       || _arm_has_void_call($op->other, $op->next, $join_addr)  # true arm
                       || _arm_has_void_call($op->next, $op->other, $join_addr)  # false arm
                       || _arm_has_die($op->other, $op->next, $join_addr) # true arm
                       || _arm_has_die($op->next, $op->other, $join_addr);# false arm
        if ($mem_branch) {
            # A value-context ternary whose arms store an ELEMENT
            # (`my $x = $c ? ($a[0]=7) : ($a[0]=8)`) would need the pushed
            # element-store value merged into a stack Phi -- not yet lowered, so
            # refuse loudly rather than lean on a downstream backend GAP.
            #
            # A field store threads on control, so the void/discarded form (the
            # method-body if/else `bump`, OPf_WANT unset = 0) merges to an Undef
            # residual below and lowers fine. But when the ternary's VALUE is
            # explicitly CONSUMED (OPf_WANT scalar=2 or list=3, e.g.
            # `my $x = $c ? ($n = 5) : ($n = 8)`), the residual IS observed and
            # must be the assigned value -- yet the field-read arms are unstamped
            # here, so the merged ternary would silently collapse to Undef (a
            # miscompile: $x would read undef, not 5). GAP loudly instead (zhi
            # 019f5368 review). The discarded form (WANT=0) is unaffected.
            my $want    = $op->flags & 3;   # OPf_WANT: 0=void/context 1=void 2=scalar 3=list
            my $is_void = $want == 1 || $want == 0;
            # A die arm aborts -- it produces no value and does not rejoin. When
            # the if/else IS the consumed expression (WANT==0 last-statement or
            # scalar), its value is the LIVE (non-die) arm's value alone; a die
            # arm contributes no value to select over (the abort never reaches
            # the merge). Detect it here so the merged value below is the live
            # arm's value, not dropped, and so the field-store GAP does not fire
            # on a die-arm branch (there is no unstamped field-read residual).
            my $die_true  = _arm_has_die($op->other, $op->next, $join_addr);
            my $false_die = _arm_has_die($op->next, $op->other, $join_addr);
            my $die_branch = $die_true || $false_die;
            die "GAP: value-context ternary with a branch-guarded element"
              . " store not yet lowered\n"
                if !$is_void && $elem_branch;
            die "GAP: a consumed value-context ternary whose arms store a class"
              . " field is not yet lowered (the arm residual is unstamped, so"
              . " the merged value would silently be Undef)\n"
                if !$is_void && !$die_branch;   # $elem_branch already died above; here it's a field store
            my $if_node = $factory->make_cfg('If',
                inputs => [$sim->control, $cond]);
            my $true_proj  = $factory->make_cfg('Proj',
                inputs => [$if_node], index => 0);
            my $false_proj = $factory->make_cfg('Proj',
                inputs => [$if_node], index => 1);
            # op->next = false arm, op->other = true arm. $walk_arm already pops
            # each arm's residual value (delta > 0) and returns it, so capture
            # each here -- a die-arm branch (below) needs the LIVE arm's value as
            # the merged result, and re-popping from the sim would find nothing.
            my ($false_arm_val, undef, $false_sim) = $walk_arm->($op->next,  $false_proj);
            my ($true_arm_val, $true_end, $true_sim) = $walk_arm->($op->other, $true_proj);
            # $walk_arm already popped each arm's residual value, so any remaining
            # stack above base is dead leftover -- drain it so merge() does not
            # build a spurious ill-typed stack Phi over a dead value (bug found in
            # 2b-1 review).
            $false_sim->pop_node while $false_sim->stack_depth > $base_depth;
            $true_sim->pop_node  while $true_sim->stack_depth  > $base_depth;
            # merge() builds the Region over [true_control, false_control], scope
            # Phis, and the memory-Phi over [true_memory, false_memory]. Adopt the
            # merged control / memory / scope into the main sim (Region-input order
            # matches merge's own [self, other] so the backend's Region handling
            # works unchanged).
            $true_sim->merge($false_sim, $factory, $if_node);
            $sim->set_control($true_sim->control);
            $sim->set_memory($true_sim->memory);
            my $merged_scope = $true_sim->scope_bindings;
            $sim->define($_, $merged_scope->{$_}) for keys %$merged_scope;
            # A die arm produces no value: the merged value is the LIVE (non-die)
            # arm's value alone, pushed whenever the block value is consumed (the
            # if/else is the last expression, WANT != explicit-void). No
            # TernaryExpr -- there is nothing to select over; the die arm aborts
            # before the merge, so the live value is unconditional at the join.
            if ($die_branch) {
                my $live_val = $die_true ? $false_arm_val : $true_arm_val;
                $sim->push_node($live_val)
                    if defined $live_val && $want != 1;
            }
            elsif (!$is_void) {
                # Non-die value context: the sim is already drained (walk_arm
                # popped), so each side falls back to an undef Constant and a
                # TernaryExpr selects -- unchanged from the pre-die behavior.
                my $true_val  = _undef_constant($factory);
                my $false_val = _undef_constant($factory);
                $sim->push_node(_make_ternary($factory, $cond, $true_val, $false_val));
            }
            return $true_end // $op->next;
        }

        # op->next = false arm, op->other = true arm.
        my ($false_val, $false_end, $false_sim, $false_delta) = $walk_arm->($op->next);
        my ($true_val,  $true_end,  $true_sim,  $true_delta)  = $walk_arm->($op->other);

        # A list-context ternary lowers via this single-value select ONLY when
        # each arm produced exactly one value (`print $c ? "y" : "n"`). An arm
        # that pushed a genuine multi-element list (`$c ? (1,2) : (3,4)`) has a
        # depth-delta > 1 -- its extra values were left unmerged; refuse loudly
        # rather than silently drop them. (delta < 1 = a value-free arm, handled
        # as _undef_constant above; that is the if/else void form, not a list.)
        die "GAP: list-context ternary with a multi-element list arm"
          . " not yet lowered\n"
            if $list_ctx && ($true_delta > 1 || $false_delta > 1);

        # Merge arm pad rebinds in EVERY context -- an assignment inside a
        # value-context arm (`my $y = $c ? ($x = 1) : 2`) is a binding side
        # effect that must become conditional exactly like the void form's.
        {
            my $base_scope  = $sim->scope_bindings;
            my $true_scope  = $true_sim->scope_bindings;
            my $false_scope = $false_sim->scope_bindings;
            my %targs = map { $_ => 1 } keys %$true_scope, keys %$false_scope;
            for my $targ (sort _scope_key_order keys %targs) {
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
                    $name eq 'return' ? 'return' : 'leavesub', $op);
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

            # `die` raises an exception -- a runtime-free abort. It becomes an
            # Unwind CFG node on the arm's control (mirroring the main walk's
            # handler): the args are the message, the arm's control advances to
            # the Unwind, and nothing is pushed to the stack (die yields no
            # value). The arm then terminates at its trailing leavesub/join. The
            # caller (_handle_cond_expr's shared control-flow path, gated by
            # _arm_has_die) merges the LIVE arm's control with this Unwind; the
            # backend lowers the Unwind to exit(255)+unreachable, so the merge's
            # die predecessor is dead and the live arm's value dominates. Only
            # the control-threaded value/modifier arms (stop_at_exit) reach here;
            # dor arms (no stop_at_exit) keep their existing behavior.
            if ($name eq 'die' && $stop_at_exit) {
                $visited->{$$op}++;
                my $args = $sim->pop_to_mark;
                my $unwind = $factory->make_cfg('Unwind',
                    inputs => [$args]);
                $unwind->set_control_in($sim->control);
                $sim->set_control($unwind);
                $op = $op->next;
                next;
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

            # A void-context statement modifier inside an arm (`$x = 5 if
            # $x < 10`) compiles to a void `and(COND, STORE)` / `or(COND,
            # STORE)`. The straight arm walk hit this `and` and stopped BEFORE
            # the join (an "untranslatable op inside an arm" GAP). Recurse into
            # the SAME void-context pad-rebind merge the main walk uses (the
            # &&/|| handler, lines ~349-445): pop the guard, walk the guarded
            # body on a snapshot stopping at this op's op_next, and merge each
            # slot the body rebound as TernaryExpr(guard, arm, base) -- arm on
            # the false side for `or`/unless. The merged bindings flow into the
            # outer if/else exactly as a plain assignment arm would.
            #
            # A pure pad/field-rebind body merges as values: the guard threads
            # through the rebound SCOPE bindings and nothing else needs pinning.
            #
            # A body carrying a statement EFFECT that rebinds no scope slot (a
            # void print / void method call, an element store, a die) cannot use
            # that merge -- the effect would walk via _step, land unpinned on the
            # shared control the guard does not gate, and the value-only merge
            # would drop or misfire it (a silent effect miscompile -- lli printed
            # nothing where perl printed `hi`). It needs REAL control flow, which
            # is exactly what the main walk's &&/|| handler already builds for
            # the same op in the same context (the $mem_branch path, ~:378):
            # If + Proj(body)/Proj(continue) before the arm walk, the effect
            # emitted on its own Proj, and merge() Regioning the arms after.
            #
            # This is the SAME shape one level down. perl compiles a one-armed
            # `if` and a statement modifier to the same `and`, so this handler
            # sees plain nested blocks -- `if (C) { if (D) { print; $n=7 } }` and
            # every `elsif` -- not just the modifier idiom it was named for.
            # Build the control flow here rather than refusing.
            if (($name eq 'and' || $name eq 'or')
                && $opmap->is_branch($name)
                && ($op->flags & 3) == 1   # OPf_WANT == OPf_WANT_VOID
                && $sim->stack_depth > 0) {
                $visited->{$$op}++;
                my $mod_stop = ${ $op->next };
                # An ELEMENT STORE in this body is still not lowered here. The
                # control-flow build below pins CONTROL effects; a store also
                # advances MEMORY, and merging that needs the memory-Phi the
                # 2b-3 path builds -- which this handler does not. Routing it
                # through anyway silently DROPPED the store (measured:
                # `if($c){if($d){$a[0]=9}} $a[0]` printed 1 where perl printed
                # 9, and both guard polarities printed the same thing). Refuse
                # loudly instead: a GAP is recoverable, a wrong answer is not.
                die "GAP: an element store inside a nested one-armed branch is"
                  . " not yet lowered (needs the memory-Phi merge)\n"
                    if _arm_has_element_store($op->other, $op->next);
                # A void CALL in this body is likewise not lowered here. Unlike
                # a Print (a pure statement effect, pinned once on its control),
                # a Call is both a value and an effect, and routing it through
                # this build emitted it on BOTH paths -- measured:
                # `if ($x>3) { helper() if $y>3 }` printed "helped" TWICE where
                # perl printed it once. Placing it correctly is the Call
                # classification problem, not this handler's. Refuse loudly.
                die "GAP: a void call inside a nested one-armed branch is not"
                  . " yet lowered (the call would be emitted on both paths)\n"
                    if _arm_has_direct_call($op->other, $op->next, $mod_stop);
                # A CONTROL effect that pins once (a print/say, a die) does
                # lower: build the same If/Proj/Region the main walk's handler
                # builds. A plain rebind body keeps the value merge below.
                my $mem_branch =
                       _arm_has_void_call($op->other, $op->next, $mod_stop)
                    || _arm_has_die($op->other, $op->next, $mod_stop);
                my $guard   = $sim->pop_node;
                my $mod_sim = $sim->snapshot;
                my $if_node;
                if ($mem_branch) {
                    $if_node = $factory->make_cfg('If',
                        inputs => [$sim->control, $guard]);
                    # `and` (if C): the body runs on the TRUE arm. `or`
                    # (unless C): the body runs on the FALSE arm.
                    my ($body_idx, $cont_idx) =
                        $name eq 'and' ? (0, 1) : (1, 0);
                    $mod_sim->set_control($factory->make_cfg('Proj',
                        inputs => [$if_node], index => $body_idx));
                    $sim->set_control($factory->make_cfg('Proj',
                        inputs => [$if_node], index => $cont_idx));
                }
                my ($mod_end, $mod_sig) = _walk_branch($cv, $op->other,
                    $mod_sim, $factory, $opmap, $visited, \my @mod_exits,
                    1, $mod_stop);
                die "GAP: function exit inside a statement modifier in an"
                  . " if/else arm not yet lowered\n"
                    if ($mod_sig // '') eq 'exited';
                # A back-edge (the body re-enters an already-visited op) is a
                # statement-modifier LOOP, not a rebind -- refuse loudly.
                die "GAP: statement-modifier loop or unhandled op inside an"
                  . " if/else arm not yet lowered\n"
                    unless defined $mod_end && ref $mod_end
                        && $$mod_end == $mod_stop;
                if ($mem_branch) {
                    # The body's residual value is discarded in void context.
                    # Drain it so merge() does not build a spurious (ill-typed)
                    # stack Phi over a dead value -- the same drain the main
                    # walk's handler does before its merge.
                    $mod_sim->pop_node
                        while $mod_sim->stack_depth > $sim->stack_depth;
                    $sim->merge($mod_sim, $factory, $if_node);
                    $op = $op->next;
                    next;
                }
                my $base_scope = $sim->scope_bindings;
                my $arm_scope  = $mod_sim->scope_bindings;
                for my $targ (sort _scope_key_order keys %$arm_scope) {
                    my $base = $base_scope->{$targ};
                    my $armv = $arm_scope->{$targ};
                    # A var introduced inside the modifier body is scoped to it;
                    # only both-sides bindings merge.
                    next unless defined $base && defined $armv;
                    next if $base == $armv;
                    my @arms = $name eq 'and'
                        ? ($armv, $base)    # if:     guard ? body : base
                        : ($base, $armv);   # unless: guard ? base : body
                    $sim->define($targ,
                        _make_ternary($factory, $guard, @arms));
                }
                $op = $op->next;
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

    # The implicit @_ argument array. Bare shift/pop operate on it, and a
    # list-assignment `my (...) = @_` destructures it. @_ is the package array
    # *main::_, so it is modeled as a StashAccess (a real array source), never a
    # string Constant.
    # Scope keys are MIXED: a pad slot is an integer, a package variable is a
    # qualified name ('main::$_'). A numeric sort over both warns and orders
    # the names arbitrarily -- latent before sigil-qualified keys made package
    # variables common, and codegen must be DETERMINISTIC. Numbers first in
    # numeric order, then names in string order.
    sub _scope_key_order {
        my $an = $a =~ /^[0-9]+$/;
        my $bn = $b =~ /^[0-9]+$/;
        return $a <=> $b if $an && $bn;
        return -1 if $an;
        return  1 if $bn;
        return $a cmp $b;
    }

    # _stash_key($node) -- the scope-map key for a package variable.
    #
    # ONE definition, derived from the NODE, so the key and the node's identity
    # cannot drift apart. They did: the aggregate read site keyed on '@' while
    # constructing a node that defaulted to '$', so `$g` and `@g` hash-consed
    # into one node while binding to two different slots.
    #
    # The sigil is part of the identity because `$g` and `@g` are unrelated
    # variables in one stash -- `$_` vs `@_` is the case that bites.
    sub _stash_key ($node) {
        return $node->stash_name . '::' . $node->sigil . $node->var_name;
    }

    sub _args_source ($factory) {
        return $factory->make('ArgsSource');
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
    #
    # A `gv[IV \&main::foo]` op (the callee of a direct sub call) does NOT hold
    # a bare GV: the pad/op slot is a B::IV whose ->RV is the callee B::CV. Its
    # sub name lives on the CV's GV, so unwrap the CV-ref to that GV.
    sub _op_gv ($cv, $op) {
        my $slot = _gv_op_slot($cv, $op);
        return undef unless $slot;
        return $slot if $slot->isa('B::GV');
        my $rcv = _cv_ref($slot);
        return $rcv ? $rcv->GV : undef;
    }

    # The GV/SV slot a gv op reads from: on the op (unthreaded) or the pad
    # (threaded). Returns undef when neither carries a value.
    sub _gv_op_slot ($cv, $op) {
        if ($op->can('sv')) {
            my $sv = $op->sv;
            return $sv if $$sv;
        }
        my $ix = $op->can('padix') ? $op->padix : $op->targ;
        if ($ix) {
            my $padl = $cv->PADLIST;
            if ($$padl) {
                my $slot = $padl->ARRAYelt(1)->ARRAYelt($ix);
                return $slot if $$slot;
            }
        }
        return undef;
    }

    # If $sv is a reference to a CV (a direct-call callee, gv[IV \&main::foo]),
    # return that B::CV; otherwise undef. Guarded on SVf_ROK so a plain-scalar
    # pad slot (an integer/undef) does not trip ->RV's "not SvROK" die.
    sub _cv_ref ($sv) {
        return undef unless $sv->can('RV') && ($sv->FLAGS & B::SVf_ROK);
        my $rv = $sv->RV;
        return $rv->isa('B::CV') ? $rv : undef;
    }

    # Resolve the callee GV of a direct-sub-call entersub op. The callee rides
    # as the LAST kid of entersub->first (an ex-list): pushmark, then the args,
    # then the callee under a nulled ex-rv2cv. Descend through null wrappers to
    # the gv and resolve it. Returns the B::GV, or undef when the callee is not a
    # plain named sub (e.g. a coderef in a pad -- F2's `$fn->()`).
    sub _entersub_callee_gv ($cv, $op) {
        return undef unless $op->can('first');
        my $list = $op->first;                  # ex-list
        return undef unless $$list && $list->can('first');
        my $kid = $list->first;
        my $callee;
        while ($$kid) {                          # last non-pushmark kid = callee
            $callee = $kid unless $kid->name eq 'pushmark';
            last unless $kid->can('sibling');
            $kid = $kid->sibling;
        }
        return undef unless $callee && $$callee;
        while ($callee->name eq 'null' && $callee->can('first')) {
            $callee = $callee->first;            # peel ex-rv2cv
        }
        return undef unless $callee->name eq 'gv';
        my $gv = _op_gv($cv, $callee);
        return ($gv && $gv->isa('B::GV')) ? $gv : undef;
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
