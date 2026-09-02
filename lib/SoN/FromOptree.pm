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
    use B::SoN::TypeLibrary;
    use SoN::FromOptree::OpMap;
    use SoN::FromOptree::StackSim;
    use SoN::FieldInfo;

    # Subst PMOP pmflags bits. /r (non-destructive) returns a new string and
    # leaves the source untouched, so it must not rebind the pad. /e (eval)
    # makes the replacement a code subtree rather than a literal string --
    # out of the runtime-free regex scope, so it is a loud GAP.
    use constant PMf_NONDESTRUCT => 0x4000000;   # 67108864
    use constant PMf_EVAL        => 0x2000000;   # 33554432 (s///e)

    # _result_stamp($node_type, \@inputs) -> SoN::IR::Stamp or undef.
    #
    # ONE DECLARATION. The result type of an operator is a fact about the
    # operator, so it is stated once, in B::SoN::TypeLibrary, and asked for
    # here. This used to carry its own copy of that table plus its own join --
    # a join with NO CAP, so `$a + $b` over two Scalars claimed Scalar rather
    # than Num, which is all `+` can yield. result_for caps.
    #
    # Returns undef -- leaving the node unstamped -- whenever the table cannot
    # say: an op it does not describe, or a join op reached with an operand
    # that nothing has narrowed. An honest GAP, never a guessed type.
    #
    # A BUILTIN CALL PASSES ITS NAME. ~180 optree ops build the one generic
    # `Call` node, so the node type alone is a question TypeLibrary can only
    # answer once for all of them -- and it answered Unknown. The name is the
    # key that separates them, and it is already in hand at both generic
    # construction sites. Which of TypeLibrary's two indices holds the answer
    # is result_for's business, not this one's; all this does is hand over the
    # key it has.
    sub _result_stamp ($node_type, $inputs, $builtin = undef) {
        my $key = defined $builtin ? [$node_type, $builtin] : $node_type;
        my $type = B::SoN::TypeLibrary::result_for($key,
            map { $_->stamp ? $_->stamp->type : undef } $inputs->@*)
            // return undef;
        return SoN::IR::Stamp->new(type => $type);
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
            && $array->operation eq 'ArrayLiteral';
        my @stamps = map { $_->stamp } $array->inputs->@*;
        return undef if !@stamps || grep { !_is_narrowed($_) } @stamps;
        my $acc = shift @stamps;
        $acc = SoN::IR::Stamp::join($acc, $_) for @stamps;
        return $acc;
    }

    # _is_aggregate_node($node) -- true iff the node is an array/hash aggregate
    # a Length can count: an ArrayRef/HashRef constructor, or a node bound to an
    # aggregate (its stamp is ArrayRef/HashRef). A scalar (e.g. a Str Constant
    # left by a symbolic `@$str` deref) is NOT an aggregate.
    #
    # @_ COUNTS, and leaving it out was a miscompile rather than an omission.
    # `ArgsSource` is the sub's argument array and arrives stamped `Array` -- a
    # different lattice member from `ArrayRef`, so a test written for the two
    # REF types alone silently excluded it. Bare `shift` is `shift @_` and
    # drains @_ exactly as `shift @q` drains @q, but the gate sent it down the
    # non-aggregate path where the drain threads no memory: two shifts in one
    # sub became two nodes with identical inputs, no memory input and no control
    # edge, so nothing ordered them and nothing told them apart.
    sub _is_aggregate_node ($node) {
        return false unless defined $node;
        my $op = $node->operation;
        return true if $op eq 'ArrayLiteral' || $op eq 'HashLiteral';
        return true if $op eq 'ArgsSource';
        my $stamp = $node->stamp;
        return false unless defined $stamp;
        my $t = $stamp->type;
        # Array/Hash COUNT TOO, and leaving them out repeated the ArgsSource
        # miscompile above one lattice member over. `Array` is what a value
        # BOUND to an aggregate carries -- an accumulated map/grep result, or
        # any array flowing through a Phi -- while `ArrayRef` is a reference to
        # one. A test written for the REF types alone silently excluded them, so
        # `scalar(@g)` fell through to the non-aggregate path and produced a
        # Coerce of the array instead of a Count of it.
        # `List` COUNTS TOO, and leaving it out is this same omission a THIRD
        # time -- first ArgsSource, then Array/Hash, now List. A list-yielding
        # builtin (`my @k = keys %h`) is stamped List, and without this
        # `scalar(@k)` emitted a Coerce of the Call instead of a Count of it.
        #
        # Every member is "a value holding N elements", and the lattice already
        # says so: Array, Hash and Scalar all descend from List. Testing
        # membership rather than enumerating the names would retire the class,
        # but the names are what the callers compare today.
        return ($t eq 'ArrayRef' || $t eq 'HashRef'
             || $t eq 'Array'    || $t eq 'Hash'
             || $t eq 'List') ? true : false;
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
    # _address_taken($cv) -> { pad targ => 1, "stash::$name" => 1 }
    #
    # WHICH VARIABLES CANNOT STAY IN VALUE-SSA. A write through a reference must
    # be visible to every later read of the name, and a value binding cannot say
    # that -- so a referenced variable moves to memory, where the existing
    # aggregate machinery already threads stores and reads.
    #
    # THE TRIGGER IS THE REFERENCE, NOT ESCAPE. `my $x = 5; my $r = \$x;
    # $$r = 9; print $x` never leaves the compiled region and is still wrong
    # under a value binding, so an escape analysis would wrongly pass it. Every
    # SSA IR draws the line here: LLVM promotes an alloca only when it is used
    # SOLELY by loads and stores, GCC gives an aliased variable virtual
    # operands, Go and Cranelift do not promote `addrtaken` locals.
    #
    # A PRE-PASS, because the decision must be known BEFORE the walk reaches a
    # read. `\$x` can appear after uses of $x, and by then the reads have
    # already been built as value bindings.
    #
    # Structural, not exec-order: srefgen can sit anywhere in the tree.
    # $root is given for the PROGRAM body, whose tree is B::main_root() rather
    # than $cv->ROOT ($cv is B::main_cv there and its ROOT is not the program).
    sub _address_taken ($cv, $root = undef) {
        my %taken;
        $root //= eval { $cv->ROOT };
        return \%taken unless $root && $$root;

        my $visit;
        $visit = sub ($op) {
            return unless ref($op) && $$op;

            if ($op->name eq 'srefgen' && $op->can('first') && ${$op->first}) {
                # The referent sits under NULLED ex-list wrappers -- measured,
                # `\$x` is srefgen -> null -> padsv and `\$g` is
                # srefgen -> null -> null -> gvsv -- so descend through them.
                my $kid = $op->first;
                $kid = $kid->first
                    while $$kid && $kid->name eq 'null'
                        && $kid->can('first') && ${$kid->first};

                if ($$kid && $kid->name eq 'padsv') {
                    $taken{ $kid->targ } = 1 if $kid->targ;
                }
                elsif ($$kid && $kid->name eq 'gvsv') {
                    my $gv = _op_gv($cv, $kid);
                    $taken{ '$' . $gv->STASH->NAME . '::' . $gv->NAME } = 1
                        if $gv && $$gv;
                }
                elsif ($$kid && $kid->name eq 'rv2sv' && $kid->can('first')
                       && ${$kid->first} && $kid->first->name eq 'gv') {
                    my $gv = _op_gv($cv, $kid->first);
                    $taken{ '$' . $gv->STASH->NAME . '::' . $gv->NAME } = 1
                        if $gv && $$gv;
                }
            }

            return unless $op->flags & 4;   # OPf_KIDS
            for (my $k = $op->first; ref($k) && $$k; $k = $k->sibling) {
                $visit->($k);
            }
        };
        $visit->($root);
        return \%taken;
    }

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
        # WHICH VARIABLES LIVE IN MEMORY, decided before the walk begins --
        # `\$x` can appear after uses of $x, and by then those reads would
        # already be built as value bindings.
        my $ctx = { mode => 'main', exits => \@exits,
                    addr_taken => _address_taken($cv,
                        defined $program_root ? B::main_root() : undef),
                    visited => \%visited,
                    # Pre-`local` bindings, restored at scope exit below.
                    local_saves => [],
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
                    \%visited, \@exits);
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
            # BLOCK EVAL: entertry/leavetry. NOT entertrycatch, which is
            # perl's `try/catch` FEATURE and the only one handled below.
            # entertry is registered BRANCH with no handler, so the generic
            # branch-skip stepped over it without walking the body, and
            # leavetry then popped a value nothing had pushed -- "Stack
            # underflow at StackSim.pm line 25". An internal crash where a
            # refusal belongs, and the worst kind: it fires BEFORE any honest
            # GAP could, masking the real diagnosis, and it names StackSim so a
            # reader goes hunting a simulator bug instead of an unhandled op.
            #
            #     3  <|> entertry(other->4) s
            #     9      <;> nextstate            <- ->next is the BODY
            #     a      <$> const[IV 1]
            #     4  <@> leavetry sK              <- ->other is where it lands
            #
            # The trap is the same shape string eval and entertrycatch use: the
            # eval either yields the body's value or, having caught, undef. Two
            # arms merging into a Region, which chalk lowers today.
            if ($name eq 'entertry') {
                my $body_sim = $sim->snapshot;
                _walk_branch($cv, $op->next, $body_sim, $factory, $opmap,
                    \%visited, undef, 1, _op_addr($op->other));

                my $undef = $factory->make('Constant',
                    value      => undef,
                    const_type => 'undef',
                    stamp      => SoN::IR::Stamp->new(type => 'Undef'));
                my $region = $factory->make_cfg('Region',
                    inputs => [$body_sim->control]);
                $sim->set_control($region);
                $sim->set_memory($body_sim->memory);

                # The body's value, or undef if it died. Three cases, and the
                # depth tells them apart:
                #
                #   deeper   the body produced a value -> Phi(value, undef)
                #   equal    a VOID eval (`eval { print "x" };`) produced none,
                #            and the caller wants none
                #   equal,   a body that ALWAYS throws (`eval { die "x" }`)
                #   wanted   pushes nothing either -- `die` builds an Unwind and
                #            yields no value -- but the eval still HAS a result,
                #            and perl says it is undef. Push the undef alone: a
                #            Phi would need two arms and there is only one.
                if ($body_sim->stack_depth > $sim->stack_depth) {
                    my $val = $body_sim->pop_node;
                    $sim->push_node($factory->make_unique('Phi',
                        inputs => [$val, $undef], region => $region));
                }
                elsif (($op->flags & 3) != 1) {   # not OPf_WANT_VOID
                    $sim->push_node($undef);
                }

                # Resume after the leavetry the body converged on.
                $op = $op->other;
                $visited{$$op}++ if $$op;
                $op = $op->next if $$op;
                next;
            }

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
                # A BARE BLOCK WITH A `continue` IS NEITHER SHAPE. It compiles
                # to a real enterloop whose nextop is the CONTINUE BODY rather
                # than the leaveloop, so the bare-block test above declines and
                # it fell through to the while-loop translator -- which walked
                # it as a loop and died "Stack underflow", an INTERNAL ERROR
                # where a named refusal belongs (perl's own t/cmd/switch.t).
                #
                # KEYED ON redoop == enter, which is what says BARE BLOCK.
                # Measured across every enterloop form:
                #
                #     bare              next=leaveloop  redo=nextstate  n==l
                #     bare + continue   next=pushmark   redo=ENTER      <- this
                #     while             next=unstack    redo=nextstate
                #     while + continue  next=stub       redo=padsv
                #     C-style for       next=padsv      redo=stub
                #
                # An earlier version keyed on `nextop is not unstack`, which is
                # true of `while + continue` and C-style `for` as well -- both
                # translate correctly today, and both were refused. The redo
                # target is the property that actually separates a block from a
                # loop.
                #
                # REFUSED because the continue body is real control flow this
                # walker does not model: it runs AFTER the block, and `last`
                # SKIPS it where `next` runs it.
                my $rd = $op->can('redoop') ? $op->redoop : undef;
                if (ref $rd && $$rd && $rd->name eq 'enter') {
                    die "GAP: a bare block with a `continue` block is not yet"
                      . " lowered -- the continue body runs after the block and"
                      . " `last` skips it, which is control flow the walker does"
                      . " not model\n";
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
            # postfix-while (`EXPR while COND`) compiles to enter/leave (NOT
            # enterloop) with a back-edge: the and/or's body arm ends in an
            # `unstack` that jumps back to the condition head (enter->next).
            #
            # DETECTED HERE, IN THE MAIN LOOP, and not moved into _step with
            # foreach -- the ORDER is the point. This runs BEFORE the walk
            # builds any condition/body node, so _translate_while_loop's
            # Phi-based re-walk owns them. Dispatching it from _step instead
            # lets the pre-walk commit the condition's nodes first, and the
            # re-walk then leaves them in the graph as orphans -- measured, 3
            # of them (Subtract, NumGt, Add), which is exactly zhi 019f29ed.
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

            # foreach: dispatched by the SHARED step handler so a loop
            # translates identically here and inside a branch arm. It used to
            # live in this loop, which _walk_branch cannot reach -- a foreach in
            # an if/else arm stopped dead at `enteriter`.

            # leaveloop - end of loop or bare block: restore any `local`.
            if ($name eq 'leaveloop') {
                _restore_locals($sim, $ctx);
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
                # Pass the CV's ROOT: the scalar reading of a multi-value
                # return is its LAST OPERAND, which only the OPTREE still
                # records -- by the time the values reach the stack they are
                # flattened and the operand boundary is gone.
                push @exits, _exit_record($sim, $factory, 'return',
                    ($cv && $$cv ? $cv->ROOT : undef));
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
                # s///e: the replacement is a code SUBTREE rather than a
                # literal, and it is walkable. It hangs off pmreplroot and is
                # intact even under the rpeep suppression this walker runs with
                # (B::SoN.pm BEGIN):
                #
                #   substcont -> null -> scope -> { ex-nextstate,
                #                                   add -> padsv $n, const 1 }
                #
                # What rpeep suppression DOES null is `pmreplstart`, the
                # computed exec shortcut into that subtree -- which is why
                # looking there found nothing and the construct read as opaque.
                # The tree was always there; the entry is its leftmost leaf,
                # and ->next from that leaf walks the body to the substcont
                # that closes it.
                #
                # /g IS THE LINE, and it is a real one. The replacement runs
                # ONCE PER MATCH -- measured, `s/a/ $n++ /ge` on "aaa" gives
                # "012" with $n at 3, while /e alone gives "0aa" with $n at 1.
                # A repeating side-effecting body is a LOOP, which one operand
                # cannot express, so /ge stays refused rather than silently
                # lowered as once-only.
                my $code_repl;
                if ($op->pmflags & PMf_EVAL) {
                    die "GAP: s///ge (code replacement run once per match) not"
                      . " yet lowered -- the replacement body repeats, which is"
                      . " a loop, not a value\n"
                        if $op->pmflags & B::PMf_GLOBAL();

                    # A CONSTANT-FOLDED /e REPLACEMENT HAS NO SUBTREE, and
                    # that is not a refusal: perl folds `s/a/ "X" . "Y" /e` at
                    # compile time and leaves pmreplroot NULL with PMf_EVAL
                    # still set. What reaches the stack is then an ordinary
                    # Constant -- the literal case -- so fall through to it
                    # rather than treating the absence as unreachable code.
                    my $rr = $op->pmreplroot;
                    goto NO_CODE_REPL unless ref($rr) && $$rr;

                    # The leftmost leaf is where execution of the subtree
                    # begins; ->next from it runs the body.
                    my $entry = $rr;
                    while (ref($entry) && $$entry && ($entry->flags & 4)
                           && ref($entry->first) && ${$entry->first}) {
                        $entry = $entry->first;
                    }
                    die "GAP: s///e replacement subtree has no entry op\n"
                        unless ref($entry) && $$entry;

                    my $repl_sim = $sim->snapshot;
                    my $base     = $repl_sim->stack_depth;
                    my @repl_exits;
                    _walk_branch($cv, $entry, $repl_sim, $factory, $opmap,
                        \%visited, \@repl_exits, 1, ${$rr});

                    die "GAP: s///e replacement that exits (return/die) not yet"
                      . " lowered\n" if @repl_exits;
                    die "GAP: s///e replacement that is not a single value not"
                      . " yet lowered\n"
                        unless $repl_sim->stack_depth == $base + 1;

                    $code_repl = $repl_sim->pop_node;
                    NO_CODE_REPL: ;
                }
                # An interpolated (multi-part) replacement -- `s/a/$y$z/`,
                # `s/a/x$y/` -- is a runtime substcont subtree (pmreplroot set),
                # NOT a single folded const. The handler below pops ONE stack
                # Constant and uses it as the whole replacement, silently
                # dropping every other part. A single interpolated variable
                # (`s/a/$y/`) folds to a compile-time Constant under
                # rpeep-suppression (pmreplroot NULL) and stays correct; only a
                # genuine subtree GAPs. Refuse loudly until it is lowered.
                # NOT FOR /e, whose pmreplroot IS the replacement subtree and
                # was consumed above. This guard is about an INTERPOLATED
                # literal (`s/a/x$y/`), where the subtree is a substcont chain
                # the handler below would silently reduce to one popped
                # Constant.
                my $replroot = $op->pmreplroot;
                die "GAP: s/// interpolated (multi-part) replacement not yet lowered\n"
                    if !defined $code_repl
                    && $replroot && ref($replroot) && $$replroot;
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
                # NO TARG MEANS $_, and $_ is nameable: it is the package
                # scalar main::_, an ordinary SSA binding in the scope map. The
                # MATCH handler beside this one already resolves it exactly this
                # way, keyed with the SIGIL because `$_` and `@_` share a glob
                # name and a name-only key hash-consed them into one node.
                #
                # Reads of $_ have always worked -- a match, a bare `print`, a
                # builtin defaulting to it. Only the WRITE was refused, and the
                # message blamed "implicit" when in fact `$_ =~ s///` was
                # refused too: the handler could key NEITHER form.
                my $targ = $op->targ;
                my $scope_key = $targ || 'main::$_';
                my $target = $sim->lookup($scope_key);
                if (!$target) {
                    $target = $targ
                        ? _make_pad_or_field($cv, $targ, $factory)
                        : $factory->make('EntryDef',
                            stash_name => 'main', sigil => '$', var_name => '_');
                    $sim->define($scope_key, $target);
                }
                # The replacement string is on the stack (pushed by const op
                # before subst) -- but ONLY for a literal replacement. Under
                # /e there is no such push: the replacement was walked from the
                # subtree above, and popping here would take an unrelated stack
                # value and stamp it on the node as a string replacement
                # contradicting the operand (measured: `s/b/ $n + 1 /e` came out
                # with replacement="5", which is $n, not the replacement).
                my $repl_node = !defined $code_repl && $sim->stack_depth > 0
                    ? $sim->pop_node : undef;
                my $replacement = '';
                if ($repl_node && $repl_node->isa('SoN::IR::Node::Constant')) {
                    $replacement = $repl_node->value // '';
                }
                # THE COMPUTED REPLACEMENT IS A SECOND OPERAND. RegexSubst
                # is a Value node and already carries inputs, so no new node
                # kind is needed: a literal replacement keeps the string field
                # and one input, a computed one adds the value beside it.
                my $node = $factory->make('RegexSubst',
                    inputs      => [$target, ($code_repl // ())],
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
                $sim->define($scope_key, $node) unless $nondestruct;
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
    # OPf_WANT as a name. 0 is "unknown" -- perl leaves the slot empty for a
    # call whose context is supplied at runtime by the caller's frame, which is
    # exactly what an inner call in last-operand position is (`entersub KS`,
    # bare K, where the outer callsites carry sKS and lKS).
    sub _want_of ($op) {
        my $w = $op->flags & 3;
        return $w == 1 ? 'void'
             : $w == 2 ? 'scalar'
             : $w == 3 ? 'list'
             :           undef;
    }

    # ANON SUB BODIES DISCOVERED DURING A WALK, as name => B::CV.
    #
    # An anon body becomes its OWN entry in `methods`, exactly as a named sub
    # does -- not a graph nested inside the AnonSub node. The nested-graph shape
    # the IR's `graph` field anticipates has no serializer arm on either side,
    # so it would be silently dropped at the seam and load as graph=undef.
    #
    # The walker cannot translate them itself (it is mid-walk on another CV), so
    # it records them here and B::SoN drains the registry and translates each
    # into the same %graphs hash every other sub lands in.
    our %ANON_BODIES;

    # A deterministic, unique name for one anon sub SITE.
    #
    #     <enclosing>::__ANON__:<line>:<targ>
    #
    # `targ` is the pad slot holding the CV -- a compile-time index, so it is
    # stable across runs and unaffected by hash seed or visit order (verified
    # under PERL_HASH_SEED/PERL_PERTURB_KEYS). It is what distinguishes two anon
    # subs on ONE line, which the line alone cannot.
    #
    # SCOPED BY THE ENCLOSING SUB, because targ is a pad index scoped to its own
    # CV: `sub f { sub {1} }` and `sub g { sub {2} }` BOTH report targ=2, and a
    # document-global methods key built from targ alone would silently drop one
    # body onto the other -- it is a hash key, so the collision does not error.
    #
    # PER SITE IS THE RIGHT GRANULARITY, not merely a workable one. For a
    # NON-CAPTURING anon sub the site IS the identity, and it survives both
    # loop iterations and call frames -- measured:
    #
    #     map { sub {7} } (1,2,3)          -> 1 CV
    #     for (1..3) { push @r, sub {7} }  -> 1 CV
    #     sub mk { sub {7} }  (mk(), mk()) -> 1 CV, SHARED across frames
    #
    # so one name per site, one CV per site, one methods entry per site.
    #
    # THIS IS ALSO WHY CAPTURING SUBS ARE REFUSED RATHER THAN DEFERRED. The
    # same measurements the other way:
    #
    #     map { my $i=$_; sub {$i} } (1,2,3)   -> 3 CVs, values 1,2,3
    #     sub mkc { my $v=shift; sub {$v} }
    #     (mkc(1), mkc(2))                     -> 2 CVs, values 1,2
    #
    # A per-site name there would give three runtime values ONE identity, which
    # is a miscompile and not a limitation. The refusal boundary is exactly
    # where this naming scheme stops being able to express the thing -- so
    # capture support is NOT an extension of this. It needs a different identity
    # (site plus captured environment), and nothing downstream may assume
    # name-is-identity once such subs exist.
    sub _anon_body_name ($cv, $op) {
        my $inner = _anoncode_cv($cv, $op);
        my $line  = ref($inner) eq 'B::CV'
            ? ( eval { $inner->START->line } // 0 ) : 0;

        # The enclosing sub names itself through its GV. A CV with no GV (the
        # program root, or an anon sub containing another) has no such name, so
        # fall back to its stash -- the scope only has to separate DISTINCT
        # enclosing CVs, and within one file the pair (line, targ) already
        # separates sites inside the same one.
        my $gv = eval { $cv->GV };
        my $enclosing =
            ( ref($gv) eq 'B::GV' && eval { $gv->NAME } )
                ? sprintf('%s::%s', eval { $gv->STASH->NAME } // 'main',
                                    $gv->NAME)
                : 'main::__PROGRAM__';

        return sprintf('%s::__ANON__:%d:%d', $enclosing, $line, $op->targ);
    }

    # The B::CV an anoncode op builds. On a threaded perl it rides in the PAD
    # rather than on the op ($op->sv is a B::SPECIAL), reached by its targ.
    sub _anoncode_cv ($cv, $op) {
        return undef
            unless $cv && ref($cv) && $op && ref($op) && $op->can('targ');
        my $inner = eval { $cv->PADLIST->ARRAYelt(1)->ARRAYelt($op->targ) };
        return ref($inner) eq 'B::CV' ? $inner : undef;
    }

    # The lexicals an anon sub closes over, by name, or () for none.
    #
    # On a threaded perl the anon CV rides in the PAD rather than on the op
    # (`$op->sv` is a B::SPECIAL), reached by its targ. A pad name is a CAPTURE
    # only when it carries PADNAMEt_OUTER -- an own lexical sits in the same
    # padlist with no flag, so counting names alone over-reports.
    sub _anoncode_captures ($cv, $op) {
        my $inner = _anoncode_cv($cv, $op);
        return () unless $inner;
        my $names = eval { $inner->PADLIST->ARRAYelt(0) };
        return () unless ref($names);

        my $PADNAMEt_OUTER = 0x1000000;
        my @captured;
        for my $i (0 .. $names->MAX) {
            my $pn = $names->ARRAYelt($i);
            next unless ref($pn) && $$pn && $pn->can('PVX');
            my $nm = $pn->PVX;
            next unless defined $nm && length $nm;
            next unless $pn->can('FLAGS') && ($pn->FLAGS & $PADNAMEt_OUTER);
            push @captured, $nm;
        }
        return @captured;
    }

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

    # _last_return_operand_is_aggregate($exit_op) -- does the return's LAST
    # operand read as a COUNT in scalar context?
    #
    # This is the whole collapse rule, and it is why the scalar reading cannot
    # be computed from the flattened values. A comma list in scalar context
    # yields its LAST OPERAND read in scalar context; an aggregate operand
    # reads as its LENGTH:
    #
    #     return (10,20,30)             -> 30   last operand is a scalar
    #     my @x=(10,20); return (99,@x) ->  2   NOT 20 -- @x's length
    #     my @x=(10,20); return (@x,99) -> 99
    #     my %h=(a=>1,b=>2); return (1,%h) -> 2
    #
    # Flattening destroys the operand boundary, so this reads the OPTREE, where
    # the boundary still exists. `padav`/`padhv`/`rv2av`/`rv2hv` are the
    # aggregate reads; anything else contributes its own scalar value.
    sub _last_return_operand_is_aggregate ($leave_op) {
        return false unless $leave_op && ref($leave_op) && $$leave_op;
        my $lineseq = $leave_op->first;
        return false unless $lineseq && $$lineseq && $lineseq->name eq 'lineseq';
        my ($last, $kid) = (undef, $lineseq->first);
        while ($kid && $$kid) { $last = $kid; $kid = $kid->sibling; }
        return false
            unless $last && ($last->name eq 'list' || $last->name eq 'return');
        my $tail;
        my $c = $last->first;
        while ($c && $$c) {
            $tail = $c unless $c->name eq 'pushmark';
            $c = $c->sibling;
        }
        return false unless $tail;
        my $n = $tail->name;
        return ( $n eq 'padav' || $n eq 'padhv'
              || $n eq 'rv2av' || $n eq 'rv2hv' ) ? true : false;
    }

    # _list_return_value($factory, \@values, $exit_op) -- the value a
    # multi-value return carries.
    #
    # BOTH READINGS, because the callee cannot choose. A perl sub is compiled
    # once and cannot see its caller's context -- that is why `wantarray` is a
    # runtime function, and why the reverted attempt at this (a418e51) failed:
    # it emitted the container and nothing ever read it back out.
    #
    # The list reading is every value, flattened, in an ArrayLiteral stamped
    # List (the type of a list is List -- these values were never bound to an
    # array, so `Array` would be the "a List is not an Array" miscompile from
    # the other direction).
    #
    # The scalar reading rides alongside as a Coerce to Scalar. Which value it
    # coerces is the collapse rule: the LAST OPERAND, read in scalar context.
    # For an aggregate last operand that is its LENGTH (`return (99,@x)` is 2,
    # not 20), so the Coerce takes a Count; otherwise it is that operand's own
    # value. The callsite's `want` says which reading to take.
    sub _list_return_value ($factory, $values, $exit_op) {
        # FLATTEN AGGREGATE OPERANDS. A list return yields all N values, and
        # perl flattens whatever an operand contributes:
        #
        #     my @x=(10,20); return (99,@x)  ->  99 10 20   (3, not 2)
        #
        # Emitting ArrayLiteral[99, ArrayLiteral[10,20]] makes a consumer
        # counting inputs read 2 where perl says 3, and hands it a nested
        # aggregate to box -- which the backend cannot tag honestly, since an
        # %Array* is not a boxed pointer to an %Array.
        #
        # Always possible here: a runtime-sized aggregate refuses upstream (a
        # non-constant range is its own GAP), so every list return that reaches
        # this point has statically known arity.
        my @flat;
        for my $v ($values->@*) {
            my $st = $v->stamp;
            if ( defined $st && ( $st->type eq 'Array' || $st->type eq 'Hash' )
                 && $v->operation =~ /\A(?:Array|Hash)Literal\z/ ) {
                push @flat, $v->inputs->@*;
            }
            else {
                push @flat, $v;
            }
        }

        my $list = $factory->make('ArrayLiteral',
            inputs => [ @flat ],
            stamp  => SoN::IR::Stamp->new(type => 'List'));

        # The scalar reading. _last_return_operand_is_aggregate reads the
        # OPTREE, where the operand boundary still exists -- the flattened
        # values above cannot answer this.
        # COUNT THE LAST OPERAND, NOT THE LIST. `return (98,99,@x)` with a
        # 2-element @x yields 2, not 3: the rule reads the last OPERAND in
        # scalar context, and the outer list's operand count is a different
        # number that happens to coincide whenever the leading operands are
        # as many as the trailing array is long.
        my $scalar_src =
            _last_return_operand_is_aggregate($exit_op)
                ? $factory->make('Count',
                    inputs => [ $values->[-1] ],
                    stamp  => SoN::IR::Stamp->new(type => 'Int'))
                : $values->[-1];

        my $scalar = $factory->make('Coerce',
            inputs   => [$scalar_src],
            from_repr => 'List',
            to_repr   => 'Scalar',
            stamp    => SoN::IR::Stamp->new(type => 'Scalar'));

        # BOTH, so the caller can put the scalar reading somewhere a consumer
        # can find it. Emitted free-floating it survived serialization only
        # because graph membership is bidirectional reachability -- it rode
        # along without any node pointing at it, which is an accident rather
        # than a contract and would not survive a dead-code pass.
        return ($list, $scalar);
    }

    # The real operand count for an op whose arity VARIES, or undef to use the
    # table's fixed pop_count.
    #
    # substr is 2-, 3- or 4-argument and the table can only state one number.
    # It said 2, so `substr($s,1,3)` popped the INDEX and LENGTH and left the
    # STRING on the stack -- a Call slicing nothing, plus a stray value that
    # made an enclosing s///e replacement look like "not a single value". Both
    # silent.
    #
    # The op knows: after the leading null (the folded pushmark) there is
    # exactly one kid per argument. Measured:
    #
    #     substr($s,1)        kids=[null,const,const]
    #     substr($s,1,3)      kids=[null,const,const,const]
    #     substr($s,1,3,"X")  kids=[null,padsv,const,const,const]
    sub _variadic_pop_count ($op, $name) {
        # BLESS TAKES ONE OR TWO ARGUMENTS and the op says which, in its
        # private field. OpMap registers a fixed 2-pop, so the one-argument
        # form popped an operand that was never pushed and died "Stack
        # underflow" -- an INTERNAL ERROR, in perl's own t/op/magic.t
        # (`sub TIEARRAY {bless[]}`). Measured on 5.42.0:
        #
        #     bless []          bless sK/1   private=1
        #     bless [], "Foo"   bless sK/2   private=2
        #
        # The one-argument form blesses into the CURRENT PACKAGE, which perl
        # resolves at compile time -- so the missing operand is not unknown,
        # it simply is not on the stack. Popping the right number is all this
        # needs; the class defaults where the backend reads it.
        return $op->private if $name eq 'bless' && $op->can('private')
                            && $op->private >= 1 && $op->private <= 2;

        # SELECT TAKES ZERO OR ONE ARGUMENT, and like bless the op says which:
        #
        #     select            select[t2] sK     private=0
        #     select(STDOUT)    select[t4] sK/1   private=1
        #
        # OpMap registers a fixed 1-pop, so the bare form popped an operand
        # that was never pushed -- "Stack underflow", in perl's own
        # t/op/select.t. The bare form returns the CURRENTLY SELECTED handle
        # and takes nothing; there is nothing missing, only a table that
        # assumed one shape.
        return $op->private if $name eq 'select' && $op->can('private')
                            && $op->private >= 0 && $op->private <= 1;

        # UNPACK TAKES EXACTLY TWO OPERANDS AND PUSHES NO MARK. OpMap
        # registers it as a 'mark' pop, so pop_to_mark found none and died
        # "No mark on mark stack" (t/op/chr.t, `unpack "U0 (H2)*", chr $_[0]`).
        # Measured, both spellings:
        #
        #     unpack("H2","A")          unpack vK/2   no pushmark
        #     unpack("U0 (H2)*","A")    unpack vK/2   no pushmark
        #
        # The template and the string, always. A fixed 2-pop is the whole fix;
        # the mark registration was simply wrong.
        return 2 if $name eq 'unpack';
        return undef unless $name eq 'substr';
        return undef unless $op->can('first');
        my $n = 0;
        my $kid = $op->first;
        while ( ref($kid) && $$kid ) {
            $n++ unless $kid->name eq 'pushmark' || $kid->name eq 'null';
            $kid = $kid->sibling;
        }
        return $n > 0 ? $n : undef;
    }

    # A CONTEXT-SENSITIVE BUILTIN'S RESULT, read from the op rather than a
    # table row.
    #
    # TypeLibrary deliberately has no signature for these: `keys` is a COUNT in
    # scalar context and the KEYS in list context, and the join of the two
    # reaches Unknown, which says nothing. Its own comment prescribes reading
    # `$op->flags` at the construction site instead -- measured, `my @k = keys
    # %h` is want=3 and `my $n = keys %h` is want=2.
    #
    # Left unstamped the Call was Unknown, and `scalar(@k)` then emitted a
    # Coerce of it rather than a Count, because _is_aggregate_node had nothing
    # aggregate to recognise. Stamping it List is what makes the count reachable.
    #
    # THE SCALAR ARM IS NOT ONE ANSWER. All four of these are a List in list
    # context, which is why they share this function -- but "Int in scalar
    # context" is true only of the two that are COUNTS. Measured on 5.42.0:
    #
    #     scalar keys %h         2       a count
    #     scalar values %h       2       a count
    #     scalar reverse "abc"   "cba"   a STRING
    #     scalar reverse @a      "321"   a STRING -- it CONCATENATES, then
    #                                    reverses the characters
    #     scalar reverse(10,20)  "0201"  string-reversed "1020", not 2010
    #     scalar sort @a         undef   not a count at all
    #
    # `reverse(10,20)` is the case that settles it: a numeric reading would be
    # 2010, and perl gives "0201". Scalar reverse is a Str whatever went in.
    #
    # SORT IS ABSENT FROM BOTH LISTS. perl warns "Useless use of sort in scalar
    # context" and folds the op away, so no Call is built and there is nothing
    # to stamp -- but a rule that is unreachable today is still a wrong rule to
    # leave written down, and it would fire the moment the op survived.
    sub _context_builtin_stamp ($op, $name) {
        state $SCALAR_IS_A_COUNT = { map { $_ => 1 } qw( keys values ) };
        state $SCALAR_IS_A_STR   = { map { $_ => 1 } qw( reverse ) };
        state $LIST_IN_LIST_CONTEXT =
            { map { $_ => 1 } qw( keys values reverse sort ) };
        return undef unless $LIST_IN_LIST_CONTEXT->{$name};
        my $want = $op->flags & 3;
        return SoN::IR::Stamp->new( type => 'List' ) if $want == 3;
        return SoN::IR::Stamp->new( type => 'Int' )
            if $SCALAR_IS_A_COUNT->{$name};
        return SoN::IR::Stamp->new( type => 'Str' )
            if $SCALAR_IS_A_STR->{$name};
        return undef;
    }

    sub _exit_record ($sim, $factory, $kind, $exit_op = undef, $is_program = 0) {
        my $value;
        # The scalar reading of a multi-value return, when there is one. It
        # rides on the Return as inputs[1] so it is reachable by contract.
        my $scalar_value;
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
            # THE CONTAINER WAS NEVER THE BUG -- the missing COLLAPSE was.
            # An earlier attempt wrapped the N values in an ArrayLiteral and
            # was reverted after `my $s = f(); print $s` emitted
            # Print <- Call(:Array): the caller received the container and
            # printed the container. That is not the round-trip being unsound,
            # it is nobody ever reading the container back out. In pure perl the
            # two legs are `my $s = f()` and `my $s = () = f()`; perl makes you
            # spell the second because it cannot see the caller's context at
            # compile time.
            #
            # WHAT THE SCALAR READING ACTUALLY IS, measured -- and it is NOT
            # "the last value", which is the leaf case of a more general rule:
            #
            #   return (10,20,30)             -> 30   last operand, a scalar
            #   return @a       (3 elements)  ->  3   last operand, an array
            #   my @x=(10,20); return (99,@x) ->  2   NOT 20
            #   my @x=(10,20); return (@x,99) -> 99
            #   my @x=();      return (1, @x) ->  0
            #
            # A comma list in scalar context yields its LAST OPERAND, read in
            # scalar context -- recursively. `(99,@x)` gives @x's LENGTH, so the
            # collapse cannot be elements[len-1] on a flattened container:
            # flattening destroys the operand boundary the rule needs.
            #
            # So the callee cannot pick one shape (it is compiled once and one
            # sub may be called both ways), but the CALLSITE can: its OPf_WANT
            # is static in the optree (entersub flags & 3 -- measured l/s/v per
            # callsite), and the operand structure is static here. Lowering this
            # means emitting all N honestly plus a scalar collapse computed from
            # the OPERAND LIST, before flattening.
            # A LONE AGGREGATE OPERAND STILL FLATTENS. `return @a` yields the
            # array's ELEMENTS, not the container -- return position imposes
            # list context, exactly as `(99,@x)` does. Measured:
            #
            #     sub agg { my @a=(10,20,30); return @a }
            #     my @l = agg();  -> 3 elements
            #     my $s = agg();  -> 3 (the count)
            #
            # A container survives a return ONLY as a reference, which is a
            # genuine scalar (ArrayRef) and is left alone by the flatten.
            # Without this the sub declared return_type=Array -- the OPERAND's
            # type where the RETURN's belongs -- sending a consumer looking for
            # a container that is never produced.
            my $lone_aggregate =
                   $args->@* == 1
                && $args->[0]->stamp
                && ( $args->[0]->stamp->type eq 'Array'
                  || $args->[0]->stamp->type eq 'Hash' );

            if ($args->@* > 1 || $lone_aggregate) {
                ($value, $scalar_value) =
                    _list_return_value($factory, $args, $exit_op);
            }
            else {
                $value = $args->@* ? $args->[-1] : undef;
            }
        }
        elsif ($sim->stack_depth > 0) {
            # The peephole optimizer elides an explicit `return` when it is the
            # trailing statement: `sub { (10,20,30) }` compiles to const pushes
            # then leavesub (no return op, no runtime pushmark). Recover the
            # multi-value shape from the leavesub's optree, not the stack.
            # The elided-return form (`sub { (10,20,30) }`, no return op) is
            # the same construct and the same problem -- see the explicit
            # branch above.
            if (_leavesub_returns_list($exit_op)) {
                # The peephole optimizer elided the `return`, so every value is
                # already on the stack; recover them in source order.
                my @vals;
                unshift @vals, $sim->pop_node while $sim->stack_depth > 0;
                ($value, $scalar_value) =
                    _list_return_value($factory, \@vals, $exit_op);
            }
            else {
                $value = $sim->pop_node;
            }
        }
        $value //= $factory->make('Constant',
            value      => undef,
            const_type => 'undef',
            stamp      => SoN::IR::Stamp->new(type => 'Undef'));
        return { control => $sim->control, value => $value,
                 ( defined $scalar_value
                     ? ( scalar_value => $scalar_value ) : () ) };
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
            # inputs[1], when present, is the SCALAR READING of a multi-value
            # list return. The callee cannot know its caller's context, so it
            # carries both faces and the callsite's `want` picks; putting the
            # scalar one here makes it reachable by contract rather than
            # riding along on bidirectional graph membership.
            my $scalar = $exits->[0]{scalar_value};
            my $ret = $factory->make_cfg('Return',
                inputs => [$value, (defined $scalar ? ($scalar) : ())]);
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
    # The GAP message for an op that is registered but builds no node. Keyed by
    # op name, phrased in terms of the SOURCE CONSTRUCT: an op name is perl's
    # implementation vocabulary and does not belong in a diagnostic about a
    # program someone wrote.
    #
    # `write` is a CALL, not a statement that lowers to a node. A format is
    # compiled into a CV parked in the glob's FORM slot (measured: it is a
    # B::FM, which isa B::CV, and its ROOT op is `leavewrite` -- the format's
    # own root, exactly as `leavesub` roots an ordinary sub). So enterwrite and
    # leavewrite are the two halves of a call ACROSS CVs, not a bracketed region
    # in one optree, which is why only enterwrite appears at the call site.
    # Compiling it needs that second CV walked plus the accumulator/formline
    # machinery, none of which exists.
    # The builtins whose FIRST operand is a filehandle. A bareword handle
    # arrives as the gv handler's name-as-string Constant, and these are the
    # ops that say it is a handle rather than a string -- `print`/`say` are
    # absent because their handle arrives through rv2gv (stamped Glob there)
    # and is guarded by OPf_STACKED, which these ops do not carry.
    my %IO_HANDLE_BUILTIN = map { $_ => 1 } qw(
        open close binmode eof fileno readline seek tell truncate
    );

    my %UNBUILT_OP_GAP = (
        enterwrite => "GAP: `write` invokes a format, which is a separate CV in"
                    . " the glob's FORM slot; compiling it needs that body"
                    . " walked and the formline accumulator, neither of which"
                    . " is built",
        leavewrite => "GAP: a format body (the CV `write` invokes) is not"
                    . " compiled",

        # `goto` transfers control and builds no node, so the jump, whatever
        # it skipped, and the label all vanished: `sub { my $x = 1; goto SKIP;
        # $x = 999; SKIP: $x }` gave Start/Constant/Return. Unlike `write`,
        # the resulting graph looks entirely reasonable, so nothing downstream
        # has any reason to object. Both forms share the op name `goto`
        # (verified with B::Concise on `goto &tgt`), so one entry covers the
        # label form and the tail-call form alike.
        #
        # Nothing currently compiled contains one (measured: 0 in chalk lib/
        # and t/, 0 in perl's t/base and t/cmd; 16 of 227 t/op files, well
        # past the frontier). This entry is insurance against a silent drop,
        # not a step toward compiling goto -- which needs real control-flow
        # support for the label form and tail-call replacement of the current
        # frame for `goto &sub`.
        # EXISTS IS NOT DEFINED, and OpMap mapped it to the Defined node --
        # over the KEY, not the slot. `exists $h{zz}` became
        # Defined(Constant("zz")): whether the STRING "zz" is defined, which it
        # always is. perl prints "no" for a missing key; the graph meant "yes".
        # A SILENT WRONG ANSWER from ordinary code.
        #
        # The two are genuinely different questions, measured on 5.42.0:
        #
        #     my %h = (a => undef);
        #     exists $h{a}     true    the key is present
        #     defined $h{a}    false   its value is not
        #
        # so no stamp could have repaired this -- the operand was wrong as well
        # as the operator. Refuse until membership is a node of its own with
        # the container and the key as its operands.
        # WANTARRAY IS A RUNTIME FUNCTION OF THE CALLER'S CONTEXT, and OpMap
        # mapped it to `Constant` -- with no `value`, so the factory died
        # "Required parameter 'value' is missing" and the sub was SILENTLY
        # SKIPPED. An internal error where a named refusal belongs.
        #
        # No constant could have been right. It has THREE values, measured on
        # 5.42.0, and which one depends on the CALLER:
        #
        #     my @l = w()    wantarray true    list context
        #     my $s = w()    wantarray false   scalar context
        #     w()            wantarray UNDEF   void context
        #
        # A sub is translated ONCE and cannot see its callers, which is
        # precisely why perl makes this a runtime function -- a fact this file
        # already states twice in prose while the table said otherwise.
        wantarray => "GAP: `wantarray` reports the CALLER's context (list,"
                   . " scalar, or void) and is therefore a runtime property"
                   . " a single translation cannot fix",

        exists => "GAP: `exists` asks whether a key is PRESENT, which is not"
                . " the same question as whether its value is defined, and no"
                . " node yet expresses it -- it would otherwise test the key"
                . " string and answer true for every missing key",

        # DELETE MUTATES AND YIELDS: it removes the key and returns the value.
        # It reached the wire as Call(delete, Constant(key)) with the KEY as its
        # only operand -- no container, and no memory edge -- so the removal was
        # invisible to every later read. The same contract push/unshift/splice
        # are held to: a mutation the graph does not thread is a silent
        # miscompile, so refuse until it is memory-modelled.
        delete => "GAP: `delete` removes a key and yields its value; the"
                . " removal is not yet threaded on the memory chain, so a"
                . " later read would still see the deleted key",

        goto => "GAP: `goto` transfers control and is not compiled; the jump,"
              . " the statements it skips, and the label would otherwise be"
              . " dropped with no diagnostic",

    );

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

        # Dispatch on FLAGS, not on class. B's SV classes nest -- PVMG isa PV,
        # isa NV, isa IV -- so asking isa('B::IV') first claims every richer SV
        # including ones that carry only a string, and returns their empty
        # integer slot. A v-string is exactly that shape: a POK-only PVMG whose
        # isa('B::IV') is true, which decoded as 0 and lost its bytes.
        #
        # IOK/NOK are asked before POK because a number that has been
        # stringified keeps its numeric slot and gains POK; POK ALONE is what
        # means "this is a string".
        my $flags = $sv->FLAGS;

        # A REFERENCE IS NOT ANY OF THE VALUE FLAGS, and asking only about them
        # sent `\2` off the end of this dispatch. perl folds `\2` to a single
        # const whose SV is ROK; measured on 5.42.0 its flags are
        #
        #     class=B::IV  ROK=1  IOK=0  NOK=0  POK=0
        #
        # so every test below failed and the bottom fallback reported a STRING
        # constant whose value was undef -- for a value perl prints as
        # SCALAR(0x...). That is a FABRICATION, not an imprecision: the
        # referent was dropped, and with the value gone `\2` and `\3`
        # hash-consed into one node.
        #
        # ROK IS TESTED FIRST because it is orthogonal to the value flags
        # rather than ranked among them. A reference SV can also carry a
        # stringified cache (POK), so asking POK first would decode the
        # "SCALAR(0x...)" text as though it were the value.
        #
        # THE REFERENT IS READ RECURSIVELY. $sv->RV is an ordinary SV, and the
        # three folded literal forms reach here with it fully populated:
        #
        #     \2      referent B::IV  IOK  2
        #     \"str"  referent B::PV  POK  str
        #     \3.5    referent B::NV  NOK  3.5
        #
        # Recursing means one arm covers all three and the referent keeps its
        # own type. (`\@a` and `\&foo` are not constants and never arrive here.)
        #
        # THE STAMP IS ScalarRef, the lattice's Ref child for a reference to a
        # single scalar -- which is what a folded literal ref always is.
        # The referent's own stamp is deliberately discarded: this constant's
        # type is the REFERENCE, not what it points at. `\2` is a ScalarRef
        # whether the referent is an Int or a Str.
        if ($flags & B::SVf_ROK()) {
            my ($referent) = _extract_const($sv->RV);
            return ($referent, SoN::IR::Stamp->new(type => 'ScalarRef'), 'ref');
        }

        if ($flags & B::SVf_IOK()) {
            return ($sv->int_value, SoN::IR::Stamp->new(type => 'Int'), 'integer');
        }
        if ($flags & B::SVf_NOK()) {
            return ($sv->NV, SoN::IR::Stamp->new(type => 'Num'), 'number');
        }
        if ($flags & B::SVf_POK()) {
            return ($sv->PV, SoN::IR::Stamp->new(type => 'Str'), 'string');
        }

        # No value flag set. Fall back on what the SV can actually offer rather
        # than guessing, so an unflagged-but-populated SV still decodes.
        return ($sv->PV, SoN::IR::Stamp->new(type => 'Str'), 'string')
            if $sv->can('PV') && $sv->isa('B::PV');

        return (undef, SoN::IR::Stamp->new(type => 'Unknown'), 'string');
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
        # CALLING AN ANON SUB NAMES ITS BODY. The callee node IS the AnonSub
        # (`sub {...}->()`), or the value a pad holds resolves to one
        # (`my $c = sub {...}; $c->()`). Without this the callee fell through
        # to 'unknown' and the AnonSub was popped and dropped -- the exact
        # silent wrong answer the old refusal was written to prevent, with the
        # body now present in `methods` and nothing pointing at it.
        my $anon_callee = $cv_node;
        $anon_callee = $sim->lookup($anon_callee->targ)
            if $anon_callee
            && $anon_callee->isa('SoN::IR::Node::PadAccess')
            && $anon_callee->can('targ');
        if ($anon_callee && $anon_callee->isa('SoN::IR::Node::AnonSub')
            && defined $anon_callee->name) {
            $call_name = $anon_callee->name;
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
        # RECORD THE CALLSITE'S CONTEXT. A callee is compiled once and cannot
        # see it (that is why `wantarray` is a runtime function), so a
        # list-returning sub carries every value AND its scalar reading, and
        # this field is how a consumer knows which one to take. Measured: the
        # same f() yields 30 in scalar context and 10,20,30 in list context,
        # with the two entersubs differing only in this flag.
        my $node = $factory->make('Call',
            inputs        => [ ($args->@* ? $args->@* : ()) ],
            dispatch_kind => 'direct',
            name          => $call_name,
            want          => _want_of($op),
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
                my $stamp = _result_stamp('Count', [$agg]);
                my %extra = defined $stamp ? (stamp => $stamp) : ();
                $sim->push_node($factory->make('Count', inputs => [$agg], %extra));
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
            my $len = $factory->make('Count',
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
            if ($top->operation eq 'ArrayLiteral') {
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

        # rv2hv IS THE SAME CASE, and had no handler. `my %c = $h->%*` fell
        # through to the list-assign path, which wraps whatever the RHS pushed
        # into a container -- so the DEREF became the single input of a
        # HashLiteral. A hash literal's inputs are 2N alternating keys and
        # values, so that node has half a pair: chalk computed a pair count from
        # it and got 0.5 (corpus F21).
        #
        # Flatten the literal referent into its pairs, exactly as the array
        # branch above does with its elements, and refuse a runtime ref for the
        # same reason -- leaving the single ref as one "pair" is a silent
        # miscompile, not a wide answer.
        if ($name eq 'rv2hv'
                && $op->can('first') && ${$op->first}
                && ($op->first->name eq 'const' || $op->first->name eq 'padsv')
                && ($op->flags & 3) == 3          # OPf_WANT_LIST
                && $sim->stack_depth > 0) {
            my $top = $sim->pop_node;
            if ($top->operation eq 'HashLiteral') {
                $sim->push_node($_) for $top->inputs->@*;
            }
            elsif ($op->first->name eq 'const') {
                $sim->push_node($top);   # not a folded HV: leave as-is
            }
            else {
                die "GAP: list-context deref of a runtime hash-ref (%\$h where "
                  . "\$h is not a literal HashRef) not yet lowered\n";
            }
            return ($op->next, 'handled');
        }

        # A PACKAGE array/hash (`@x`, `%h`) reaches here as rv2av/rv2hv over a
        # `gv`. The gv handler pushed the variable's NAME as a string Constant
        # (it is the callee name for an entersub), and rv2sv pops that Constant
        # and replaces it with a EntryDef for a package SCALAR -- but no
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
        #   @_        _args_source builds a EntryDef for *main::_ -- a real
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
        # arg-array EntryDef, and main::ENV is the process environment rather
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

            # Discard the gv's NAME Constant: it is the callee-name token an
            # entersub consumes, not a value.
            $sim->pop_node;

            # Sigil-qualified, as the scalar site is: one stash can hold
            # `$g` and `@g` as unrelated variables.
            my $agg_sigil = $op->name eq 'rv2hv' ? '%' : '@';
            my $key      = $gv->STASH->NAME . '::' . $agg_sigil . $gv_name;
            my $existing = $sim->lookup($key);

            # `local @x` restores exactly as `local $g` does -- same key, sigil
            # included -- so it records the same save for the scope exit below.
            if ($op->private & 128) {   # OPpLVAL_INTRO
                # Same per-iteration problem as the scalar site above.
                die "GAP: `local` inside a loop body is not yet lowered --"
                  . " it restores once per ITERATION, not at loop exit\n"
                    if $ctx->{in_loop_body};
                push $ctx->{local_saves}->@*, { key => $key, node => $existing };
            }

            # An LVINTRO target (`our @x = ...`) or an OPf_MOD use is a
            # DEFINITION site: push a fresh EntryDef as the name token the
            # following aassign defines from. A plain read of a bound name
            # pushes the bound VALUE, exactly as padav does.
            #
            # OPf_REF alone is NOT a definition -- it means the consumer wants
            # the AGGREGATE ITSELF rather than a flattened list. `$#x` is
            # exactly that shape (rv2av sKR/1 feeding av2arylen), and treating
            # it as a target pushed a fresh EntryDef instead of the bound
            # ArrayRef, so the length had nothing to measure. Measured: `$#x`
            # GAPped on Length.operand for every array size.
            my $is_target = ($op->private & 0x80)      # OPpLVAL_INTRO
                         || ($op->flags & 0x20);       # OPf_MOD
            if ($existing && !$is_target) {
                $sim->push_node($existing);
            }
            else {
                my $node = $factory->make('EntryDef',
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
                # Demotion is built: _address_taken marks the variable before
                # the walk, its reads carry the current memory version, and its
                # writes are Assign stores on the memory chain. Fall through and
                # let srefgen build the reference over the location.
                ()
            }
        }

        # rv2gv MEANS "THE GLOB ITSELF IS THE VALUE HERE", and that is the one
        # signal separating a glob used as a value from a glob used as a name.
        # The gv handler pushes the glob's NAME as a Str Constant, which is
        # correct where a name is wanted -- naming a callee, keying %ENV -- and
        # a fabrication where the glob is the value. Measured, the optree draws
        # the distinction for us:
        #
        #     foo()          gv[IV \&main::foo] -> entersub       no rv2gv
        #     \*STDOUT       gv[*STDOUT] -> rv2gv -> srefgen      rv2gv
        #     *STDIN         gv[*STDIN]  -> rv2gv                 rv2gv
        #
        # So restamp the name Constant as a Glob here rather than teaching the
        # gv handler to guess from context it cannot see. `\*STDOUT` then
        # becomes Ref(Glob), and B::SoN's Ref rule -- which follows its
        # operand's kind -- yields GlobRef instead of calling it a ScalarRef.
        #
        # THE VALUE IS KEPT, NOT DISCARDED. The name is the only handle on
        # WHICH glob this is (there is no address at compile time), and a
        # consumer needs it to resolve STDOUT. What changes is the claim about
        # its TYPE: `Glob` says "the handle named STDOUT", where `Str` said
        # "the six-character string STDOUT" -- which is what perl prints for
        # `print "STDOUT"` and emphatically not what it prints for
        # `print \*STDOUT` (GLOB(0x...)).
        if ($name eq 'rv2gv' && $sim->stack_depth > 0) {
            my $top = $sim->peek_node;
            if ($top && $top->isa('SoN::IR::Node::Constant')
                && ($top->const_type // '') eq 'string'
                && $top->stamp && $top->stamp->type eq 'Str') {
                $sim->pop_node;
                $sim->push_node($factory->make('Constant',
                    value      => $top->value,
                    const_type => 'glob',
                    stamp      => SoN::IR::Stamp->new(type => 'Glob')));
                return ($op->next, 'handled');
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
                my $arr = $factory->make('ArrayLiteral', inputs => \@elems);
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
        # STRING EVAL IS A Str -> Code COERCION, and the producer's job is to
        # STATE that, not to decide whether it can be lowered. `eval STRING`
        # takes a value and returns a first-class CODE value -- storable,
        # passable, callable -- so it is an ordinary value conversion.
        #
        # This used to be a hand-written refusal in %UNBUILT_OP_GAP next to
        # `goto`, which meant ONE eval refused the WHOLE FILE: perl's own
        # t/base/lex.t translated 10 nodes and stopped. Emitting the node
        # instead leaves a complete graph with exactly one un-lowerable member,
        # which is strictly more information and the shape the rest of the
        # producer already uses. The consumer refuses it at the Code machine
        # type, which is where that knowledge lives (T1 states, T2 decides).
        #
        # THE TRAP IS A REGION, NOT A TryCatch. `eval "die"` returns undef and
        # sets $@ without unwinding, so the graph must not claim the expression
        # always yields a value. Block eval already models exactly that -- walk
        # both arms, merge() to a Region -- and this reuses it. A TryCatch node
        # type exists but has never been constructed and chalk cannot lower one
        # (it needs an LLVM landingpad plus a personality function, a design
        # question for a runtime-free backend). Wrapping in one would add a
        # SECOND un-lowerable node to describe a refusal, and would misattribute
        # the blocker: the gate would name the wrapper when the unsupported
        # thing is the conversion.
        if ($name eq 'entereval') {
            my $src = $sim->pop_node;
            my $code = $factory->make('Coerce',
                from_repr => (defined $src->stamp ? $src->stamp->type : 'Str'),
                to_repr   => 'Code',
                inputs    => [$src],
                stamp     => SoN::IR::Stamp->new(type => 'Code'));
            # The trap: the eval either yielded its value or caught and returned
            # undef. Two arms merging is the same shape block eval builds.
            my $undef = $factory->make('Constant',
                value      => undef,
                const_type => 'undef',
                stamp      => SoN::IR::Stamp->new(type => 'Undef'));
            # THE COERCE IS AN EFFECT, NOT A PURE VALUE, so it is pinned to
            # the control chain. A void `eval q{1};` discards the result, and
            # an unpinned value node with no consumer is dead: the whole eval
            # VANISHED from the graph, leaving a bare Region -- the same silent
            # drop `write` and `goto` are refused for. An eval can die and can
            # define subs; it happens whether or not anyone reads its value.
            $code->set_control_in($sim->control);
            $sim->set_control($code);
            my $region = $factory->make_cfg('Region', inputs => [$code]);
            $sim->set_control($region);
            my $value = $factory->make_unique('Phi',
                inputs => [$code, $undef], region => $region);
            # Void context discards the value; the effect above still stands.
            $sim->push_node($value) unless ($op->flags & 3) == 1; # OPf_WANT_VOID
            return ($op->next, 'handled');
        }

        if ($name eq 'padsv') {
            my $targ = $op->targ;
            # A deref padsv ($r->[0], $r->{k}) carries OPf_MOD for
            # autovivification but is READING $r to dereference it -- resolve
            # it to the bound value (the ref), not a fresh lvalue PadAccess, so
            # the following rv2av/rv2hv+aelem/helem sees the aggregate.
            my $is_deref  = ($op->private & 48); # OPpDEREF (AV|HV|SV)
            # OPf_MOD MARKS A POTENTIAL LVALUE, NOT AN ACTUAL WRITE. perl leaves
            # it set on a comparison's first operand after folding a dead branch
            # arm (`if (0) {...} elsif ($x != $y)` compiles that $x as
            # `padsv sM`), and treating it as an assignment target pushes a
            # FRESH unbound PadAccess instead of the slot's live value. Inside a
            # loop the comparison then reads a node nothing defines while the
            # real value sits in the header Phi -- two nodes for one variable.
            # A comparison operand is a READ (see _is_comparison_optree_op), so
            # it keeps its binding.
            # The comparison is not necessarily the NEXT op: a binary
            # comparison pushes both operands first, so `$x != $y` runs
            # padsv, padsv, ne. Scan forward over the sibling operand pushes
            # (pad reads and constants) to the op that consumes them.
            my $mod_but_compared = 0;
            if ($op->flags & 32) {
                my %seen;
                for (my $o = $op->next; $$o && !$seen{$$o}++; $o = $o->next) {
                    my $m = $o->name;
                    next if $m =~ /^(padsv|padav|padhv|const|gvsv|null)$/;
                    $mod_but_compared = _is_comparison_optree_op($m);
                    last;
                }
            }
            my $is_lvalue = ($op->flags & 32) && !$is_deref
                                              && !$mod_but_compared; # OPf_MOD
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

            # A DEMOTED SLOT HAS NO VALUE BINDING TO PUSH. Its value lives in
            # memory, so a read is a location node threaded to the memory
            # version that produced it -- exactly what an element read does
            # (`Subscript(array, index, Assign)`). Pushing $existing here is
            # what folds `$x = 5; $x = 9; print $x` to the constant 9, which is
            # right without aliasing and wrong the moment `\$x` exists.
            if ($ctx->{addr_taken}{$targ}) {
                # Built with the memory input rather than mutated after: a
                # node's inputs are a construction :param, and the memory
                # version is what makes two reads either side of a store
                # DIFFERENT nodes rather than one hash-consed read.
                my $read = $factory->make('PadAccess',
                    targ     => $targ,
                    varname  => _padname($cv, $targ),
                    (defined $sim->memory ? (inputs => [ $sim->memory ]) : ()),
                );
                $sim->push_node($read);
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
                    && $existing->operation eq 'ArrayLiteral') {
                $sim->push_node($_) for $existing->inputs->@*;
                return ($op->next, 'handled');
            }
            # AN ASSIGNMENT TARGET IS THE SLOT, NOT ITS CURRENT VALUE.
            # `@a = ()` reads @a with OPf_MOD set, and pushing $existing there
            # handed the aassign the OLD container as its LHS -- so the clear
            # rebound nothing and a later `scalar(@a)` counted the pre-clear
            # elements. Measured: `my @a=(1,2,3); @a=(); print scalar(@a)`
            # gave 3 where perl gives 0, silently.
            #
            # MEASURED ACROSS ALL THREE USES, because REF|MOD alone does not
            # separate them -- keying on that broke every `for my $x (@a)`:
            #
            #     @a = ()             f=0xb3  REF|MOD  want=LIST     target
            #     my @a = (1,2,3)     f=0xb3  REF|MOD  want=LIST     target
            #     for my $x (@a)      f=0x32  REF|MOD  want=SCALAR   source
            #     shift @a            f=0x33  REF|MOD  want=LIST(!)  operand
            #     scalar(@a)          f=0x02  --       want=SCALAR   read
            #
            # THE FLAGS DO NOT SEPARATE THESE. `shift @a` is f=0x33 and the
            # clear target f=0xb3 -- identical but for LVAL_INTRO, which the
            # DECLARATION also sets. Two attempts keyed on flags each broke a
            # different case (foreach sources, then shift's element stamp).
            #
            # THE CONSUMER separates them, and it is one op away:
            #
            #     @a = ()      padav -> aassign     target
            #     my @a = ()   padav -> aassign     target
            #     shift @a     padav -> shift       operand
            #     push @a, 4   padav -> const       operand
            #     for (@a)     padav -> enteriter   source
            #
            # An aassign consumer means the binding is about to be REPLACED, so
            # the slot must be pushed rather than its current value; anything
            # else wants the container it already has.
            # DESCEND THROUGH nulls. Under the rpeep suppression this walker
            # runs with, the chain keeps the null placeholders perl would
            # otherwise remove -- raw B shows padav->aassign, the walker sees
            # padav->null->aassign. Matching $op->next directly found `null`
            # and classified every target as a plain read.
            my $consumer = $op->next;
            $consumer = $consumer->next
                while $consumer && $$consumer && $consumer->name eq 'null';
            my $is_assign_target =
                $consumer && $$consumer && $consumer->name eq 'aassign';
            if ($existing && !$is_assign_target) {
                $sim->push_node($existing);
            } else {
                my $node = _make_pad_or_field($cv, $targ, $factory);
                $sim->define($targ, $node) unless $existing;
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
                # gv keeps its short NAME (the existing EntryDef contract).
                $value = ($gv->STASH->NAME eq 'main' && $gv->NAME eq 'ENV')
                    ? 'main::ENV'
                    : $gv->NAME;
            }
            # `@_` is the ARGUMENT LIST, not a name. `$_[0]` reaches it as
            # gv[*_] under an rv2av, and this handler pushed the NAME as a
            # string Constant -- so the array was represented three different
            # ways across the IR (EntryDef for `shift`, a bare Constant
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
        # :Str); any other package scalar is a EntryDef named from its GV.
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
                # fresh EntryDef as a NAME TOKEN for sassign to define from;
                # an rvalue over a bound name pushes the bound VALUE.
                #
                # The EntryDef that survives is the ENTRY DEFINITION: the
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
                # `local` REBINDS FOR A SCOPE AND RESTORES AT ITS EXIT, and
                # under SSA that restore is a REBIND: a package scalar is a
                # value binding in the scope map, so putting the old node back
                # is the whole operation -- no cell, no save/restore of memory.
                #
                # Measured, every scope shape restores and all of them end at
                # `leave` or `leaveloop`:
                #
                #   bare block   ... sassign leaveloop leave
                #   if arm       ... sassign leave leave
                #   do block     ... sassign leave leave
                #   sub body     ... sassign leave
                #
                # A LOOP BODY IS STILL REFUSED, further down, because it
                # restores PER ITERATION -- `for (1..3) { print $g; local $g =
                # $g+1; print $g }` prints 121212, each pass starting from the
                # outer value. That is a Phi interaction the straight-line
                # shapes do not have, and getting it wrong is silent.
                if ($op->private & 128) {   # OPpLVAL_INTRO
                    # A LOOP BODY RESTORES PER ITERATION, which the
                    # scope-exit rebind cannot express: the save is taken once,
                    # on the pass that walks the body, so restoring it at the
                    # loop's exit gives every iteration the last pass's value.
                    # Measured, `for (1..3) { print $g; local $g = $g+1;
                    # print $g }` prints 121212 -- each pass starts from the
                    # OUTER value -- while the graph built a loop-carried Phi
                    # for $g, the opposite recurrence.
                    die "GAP: `local` inside a loop body is not yet lowered --"
                      . " it restores once per ITERATION, not at loop exit\n"
                        if $ctx->{in_loop_body};
                    my $key = $gv->STASH->NAME . '::$' . $gv->NAME;
                    push $ctx->{local_saves}->@*,
                        { key => $key, node => $sim->lookup($key) };
                }

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
                    my $node = $factory->make('EntryDef',
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

        # Any other rv2sv IS a scalar dereference: `$$r` reads through the
        # reference the kid left on the stack. Distinct from the gv case above,
        # which is a named variable read and not a dereference at all.
        #
        # PostfixDeref is the existing vocabulary for this -- it carries the
        # sigil and was already registered and serialized, but built ZERO times.
        #
        # The `${\ EXPR }` idiom is the same node: a ref to a temporary, read
        # straight back through. That is what kept base/lex.t off 9/9.
        if ($name eq 'rv2sv') {
            die "GAP: scalar dereference with no reference operand not yet"
              . " lowered\n"
                unless $sim->stack_depth > 0;

            my $ref = $sim->pop_node;

            # AN LVALUE DEREF IS A LOCATION, and the SAME node names it. `$$r`
            # on the left of an assignment is where to store; on the right it
            # is what to load. PostfixDeref is that location either way, and
            # the STORE is the sassign handler's job -- it already has a
            # demoted-slot path that emits Assign(location, value) on the
            # memory chain.
            #
            # This works because taking a reference already DEMOTES the
            # referent: `my $r = \$v` marks $v address-taken, so $v lives in
            # memory and every read of it carries a memory version. A write
            # through $r is a store to that same location, which is what makes
            # it visible to later reads of $v -- and to any alias of $r.
            my $node = $factory->make('PostfixDeref',
                inputs => [$ref],
                sigil  => '$',
                stamp  => SoN::IR::Stamp->new(type => 'Scalar'));
            $sim->push_node($node);
            return ($op->next, 'handled');
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
            # A runtime pattern is ALSO on the stack, pushed by the
            # transparent regcomp (OpMap SKIP, [1,undef,1]) AFTER the subject.
            # Pop it here, before the subject, because that is push order --
            # `=~` is a binop and its operand order is the binop's, not
            # something to be recovered. Undef for a literal pattern, whose
            # pattern rides on the op itself and never reaches the stack.
            #
            # This used to refuse the stacked+runtime pair outright, on the
            # reasoning that two stack values needed an order established
            # first. They have one. Popping the subject FIRST, as the old
            # non-refusing path did, would have taken the PATTERN -- the two
            # operands inverted, silently, since the graph still holds a Match
            # with two inputs either way.
            my $matcher = defined $pattern ? undef : $sim->pop_node;

            my $target;
            if ($op->flags & 64) {   # OPf_STACKED: subject pushed by a kid op
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
                # definition; building a fresh EntryDef here would bypass the
                # binding and reach the backend as an untyped entry definition.
                # Keyed by SIGIL as well as name: `$_` and `@_` are
                # different variables sharing the glob name `_`, and a
                # name-only key bound them to the same slot -- which then
                # hash-consed to one node feeding both a `shift @_` and this
                # match.
                my $key = 'main::$_';
                $target = $sim->lookup($key);
                unless ($target) {
                    $target = $factory->make('EntryDef',
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
                    inputs => [$target, $matcher],
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
        # `sub { ... }` -- the body is not lowered, and shipping a Call to a
        # callee named "unknown" is a silent wrong answer. Measured:
        #
        #     my $c = sub { 42 }; print $c->();
        #       perl prints 42
        #       graph: Constant(undef), Call(direct, name="unknown")
        #       stderr: "syntax OK"
        #
        # Same class as the map/grep drop below, one construct over, and it
        # reaches ordinary code: `apply(sub { 7 })` was equally silent.
        #
        # THE BODY IS REACHABLE, so this is a refusal pending a decision rather
        # than a missing capability. On a threaded perl the CV rides in the PAD,
        # not on the op -- `$op->sv` is a B::SPECIAL, while
        # PADLIST->ARRAYelt(1)->ARRAYelt($op->padix) is the B::CV with a
        # walkable START. What is undecided is the calling convention: a named
        # sub becomes its own graph in `methods` referenced by name, and an
        # anonymous one should almost certainly follow that, but it is a wire
        # decision.
        if ($name eq 'anoncode') {
            # SAY WHICH KIND. Both still refuse, but they need different work
            # and one message hides which one a corpus file actually hit.
            #
            # Capture is decidable here: a captured pad name carries the OUTER
            # flag in the anon CV's padlist, while an own lexical does not.
            # `does the pad have names` is the WRONG test -- it counts
            # `sub { my $y=1; $y }` as a closure when that body needs nothing
            # from its enclosing scope.
            my @captured = _anoncode_captures($cv, $op);
            die "GAP: an anonymous sub closing over "
              . join(', ', @captured)
              . " is not yet lowered -- the body is reachable, but the"
              . " captured variables have no wire representation yet\n"
                if @captured;

            # LOWERED. The body becomes its own `methods` entry under a
            # deterministic per-site name, and the AnonSub node carries that
            # name -- the same shape a named sub already uses, so no nesting
            # and no new addressing.
            my $body = _anoncode_cv($cv, $op)
                or die "GAP: an anonymous sub whose body could not be reached"
                     . " from the pad is not yet lowered\n";

            # THE NAME MUST REACH A CONSUMER, or the body is emitted with
            # nothing pointing at it and the call goes nowhere. Measured when
            # this was missing: `my @subs = (sub{1}, sub{2}); $subs[0]->()`
            # emitted two bodies and two Call(name="unknown") -- perl prints 3,
            # the graph calls nothing. That is the original silent-drop defect
            # returned, and worse, because the graph now looks complete.
            #
            # WHAT MATTERS IS WHETHER THE NODE IS CONSUMED, not which op comes
            # next. An earlier guard keyed on the following op and got this
            # wrong twice in both directions: it refused `sub {...}->()` (the
            # entersub is reached through a null) and, once that was fixed, it
            # still refused `$SIG{__WARN__} = sub {...}` -- a hash-element
            # Assign that DOES consume the AnonSub and names the body
            # correctly. The op sequence is a proxy for consumption and a bad
            # one; consumption is checkable directly, after the fact.
            #
            # So the node is built unconditionally here and the whole graph is
            # checked once at the end (see _refuse_orphan_anon_bodies), which
            # is the only place that can see whether anything referenced it.

            my $anon_name = _anon_body_name($cv, $op);
            $ANON_BODIES{$anon_name} //= $body;

            # CodeRef, NOT Code. `sub { ... }` in an expression yields a code
            # REFERENCE -- measured, `ref(sub{1})` is CODE and reftype agrees --
            # and the distinction is load-bearing rather than cosmetic. In this
            # lattice Code hangs off Unknown while CodeRef is a child of Ref:
            #
            #     Code     <: Ref  no    <: Scalar  no
            #     CodeRef  <: Ref  yes   <: Scalar  yes
            #
            # so `my $c = sub {...}` gave a scalar slot a type that cannot live
            # in a scalar, and every merge it reached collapsed:
            #
            #     join(Code,    Undef) = Unknown
            #     join(CodeRef, Undef) = Scalar
            #
            # `Code` is the CV itself, which no perl scalar ever holds. The one
            # place it is still right is entereval's compiled body, which is an
            # intermediate rather than a value in a slot.
            my $node = $factory->make('AnonSub',
                inputs => [],
                name   => $anon_name,
                stamp  => SoN::IR::Stamp->new(type => 'CodeRef'));
            $sim->push_node($node);
            return ($op->next, 'handled');
        }

        # map/grep/sort WITH A BLOCK: the block is not lowered, and shipping
        # the list without it is a SILENT WRONG ANSWER -- the worst outcome the
        # refuse-or-lower contract exists to prevent.
        #
        # Measured, `my @m = map { $_ * 2 } (1,2)` emitted a well-formed graph
        # with no Multiply in it anywhere and no diagnostic at all:
        #
        #     Start, Constant x3, Call(mapstart), ArrayLiteral, MemStart,
        #     Subscript, Coerce, Print, Return
        #
        # The cause is in OpMap: mapstart/grepstart map to a generic Call that
        # consumes the LIST, while mapwhile/grepwhile -- which ARE the block
        # execution -- are marked BRANCH, so the generic branch-skip steps over
        # the body without walking it. The block is a real subtree
        # (`gvsv $_`, `const 2`, `multiply`, looping back to mapwhile); nothing
        # translates it. Reported by chalk, corpus F18/F19/F20.
        #
        # LOWERED as a counted loop with a ListAppend accumulator. map/grep are
        # LOOPS -- they carry mapwhile/grepwhile the way `while` carries
        # enterloop -- so the foreach lowering does the control flow; only the
        # variable-length output needed new vocabulary. Measured shape:
        #
        #     pushmark, pushmark, <input list>, mapstart,
        #     mapwhile(other-> BODY), ... goto mapwhile
        #
        # so the input is pop_to_mark and the body is mapwhile->other. `$_` is
        # `gvsv[*_]`, keyed 'main::$_' exactly as an implicit foreach iterator.
        # SPLIT PUSHES NO MARK IN ANY FORM, and OpMap registers it as a 'mark'
        # pop -- so pop_to_mark found none and died "No mark on mark stack", an
        # INTERNAL ERROR where a named refusal belongs. Measured on 5.42.0,
        # every spelling:
        #
        #     my @x = split(/,/,$s)   split(/","/ => @x:1,3) vK/LVINTRO,ASSIGN,LEX
        #     @y = split(/,/,$s)      split(/","/ => @y:2,3) vK/ASSIGN,LEX
        #     my $n = split(/,/,$s)   split                  sK/IMPLIM
        #
        # A first version refused only the SCALAR form, on the theory that the
        # list form "fused, has a mark". It does not: the list form fuses the
        # ASSIGNMENT into the split op (`=> @x:1,3`) and likewise pushes no
        # mark, so `my @x = split /\n/, $s` -- an extremely common idiom --
        # was still an internal error. The scalar case was the symptom I
        # happened to measure first, not the shape of the bug.
        #
        # REFUSED IN ALL FORMS. The list form's target array is bound INSIDE
        # the op, which nothing here models, and the scalar form yields a field
        # count over fields that are never built. Both are real work; neither
        # is a stack bug, which is what the internal error was hiding.
        if ($name eq 'split') {
            die "GAP: `split` is not yet lowered -- the list form binds its"
              . " target array inside the op and the scalar form yields a"
              . " field count, and neither is modelled\n";
        }

        if ($name eq 'mapstart' || $name eq 'grepstart') {
            ( my $word = $name ) =~ s/start\z//;
            my $items = $sim->pop_to_mark;
            die "GAP: $word over an empty list not yet lowered\n"
                unless $items->@*;

            # One aggregate operand IS the list; anything else is a literal
            # list of elements, wrapped exactly as `for my $i (1,2,3)` wraps it.
            #
            # STAMPED List, because THE TYPE OF A LIST IS List -- a real
            # lattice member directly under Unknown, with Array/Hash/Scalar
            # beneath it. Every other ArrayLiteral site says what it built
            # (`my @a = (...)` is Array, `[...]` is ArrayRef); left silent this
            # one fell through to Unknown, the TOP, which asserts nothing about
            # a value whose type is known right here. Not Array: these elements
            # were never bound to an array, and calling them one repeats the
            # "a List is not an Array" miscompile from the other direction.
            my $input = ($items->@* == 1 && _is_aggregate_node($items->[0]))
                ? $items->[0]
                : $factory->make('ArrayLiteral', inputs => [$items->@*],
                    stamp => SoN::IR::Stamp->new(type => 'List'));

            my $while_op = $op->next;
            die "GAP: $word without a ${word}while op\n"
                unless $$while_op && $while_op->name eq $word . 'while';

            # $op (mapstart/grepstart) carries the CONTEXT in its OPf_WANT --
            # sK for a scalar reading, lK for a list one -- and the accumulator
            # push needs it to decide between the result list and its count.
            _translate_foreach_array($cv, $op, $sim, $factory, $opmap,
                $ctx->{visited}, $input, 'main::$_',
                scalar $while_op->other, $word, $op);

            # The whole construct is consumed: resume after the loop.
            return ($while_op->next, 'handled');
        }

        # `sort` only carries a block when perl could not FOLD it. Measured:
        #
        #     sort { $a <=> $b }              lK/NUM        folded, no block
        #     sort { $b <=> $a }              lK/DESC,NUM   folded, no block
        #     sort { length($a) <=> ... }     lKS*          OPf_STACKED, a real
        #                                                   comparator subtree
        #
        # So the folded forms are not refused here -- they have no block to
        # drop -- and OPf_STACKED is what marks one that would be.
        if ($name eq 'sort' && ($op->flags & 64)) {   # OPf_STACKED
            die "GAP: sort with a comparator BLOCK is not yet lowered -- the"
              . " comparator would be dropped and the list left unsorted\n";
        }

        if ($name eq 'undef') {
            # `undef EXPR` AND `EXPR = undef` ARE NOT ONE OPERATION. Measured:
            #
            #   my @a=(1,2,3); undef @a;   -> scalar(@a) is 0  (emptied)
            #   my @b=(1,2,3); @b = undef; -> scalar(@b) is 1  (one undef elem)
            #
            # For a SCALAR they coincide, and that case lowers: perl compiles
            # `undef $x` to a single `undef[$x] vK/TARGMY` carrying its OWN
            # targ, so the target is named on the op and nothing needs popping.
            # It is exactly the rebind performed below for the no-operand form;
            # the refusal fired first only because `undef $x` also sets
            # OPf_KIDS.
            #
            # An AGGREGATE operand is a different operation -- emptying a
            # container, not rebinding a name -- and modelling it as a rebind to
            # Undef would produce the one-element array `@a = undef` means. That
            # stays refused.
            # THE OPERAND IS NAMED BY THE KID, not by the op's targ. Under
            # the rpeep suppression this walker runs with there is no TARGMY
            # fusion -- measured, `undef $x` and `undef @a` are both
            # `flags=0x6 private=0x1 targ=0` and indistinguishable on the op
            # itself. The kid tells them apart and carries the pad slot:
            #
            #     undef $x   kid=padsv  targ=1
            #     undef @a   kid=padav  targ=1
            #     undef %h   kid=padhv  targ=1
            #     undef $g   kid=rv2sv  targ=0   (package scalar)
            my $undef_targ;
            if ($op->flags & 4) {                               # OPf_KIDS
                my $kid = $op->can('first') ? $op->first : undef;
                my $kname = ( ref($kid) && $$kid ) ? $kid->name : '';

                # A PACKAGE SCALAR IS THE SAME OPERATION AS A LEXICAL ONE.
                # `undef $a` rebinds that name to undef exactly as `undef $x`
                # does; only the slot is named differently -- a stash key
                # rather than a pad index. It was refused only because the kid
                # is a gvsv (or rv2sv) instead of a padsv, which is a fact
                # about how perl spells the operand, not about the operation.
                #
                # The kid has already pushed the variable's current value, and
                # a package scalar's node carries its own name, so the key
                # comes from the node rather than from a targ.
                if ($kname eq 'gvsv' || $kname eq 'rv2sv') {
                    my $cur = $sim->stack_depth > 0 ? $sim->pop_node : undef;
                    my $node = _undef_constant($factory);
                    if ($cur && $cur->can('stash_name') && $cur->can('sigil')
                        && ( $cur->sigil // '' ) eq '$') {
                        $sim->define(_stash_key($cur), $node);
                    }
                    # No recognisable name to rebind: pushing the constant
                    # would silently drop the write, so refuse instead.
                    else {
                        die "GAP: undef(EXPR) on a package scalar whose name"
                          . " could not be resolved ($kname) not yet lowered\n";
                    }
                    $sim->push_node($node);
                    return ($op->next, 'handled');
                }

                # AN AGGREGATE IS EMPTIED, NOT REBOUND -- and an EMPTY
                # container expresses that exactly. `undef @a` and `@a = ()`
                # are the same operation (both leave 0 elements); what neither
                # is is `@a = undef`, which leaves ONE undef element. Binding
                # the slot to an empty ArrayLiteral/HashLiteral is the `@a=()`
                # shape, which already lowers.
                if ($kname eq 'padav' || $kname eq 'padhv') {
                    my $targ = $kid->targ
                        or die "GAP: undef(EXPR) on an unnamed aggregate not"
                             . " yet lowered ($kname)\n";
                    # The kid pushed the container; this is a WRITE of the slot.
                    $sim->pop_node if $sim->stack_depth > 0;
                    my $empty = $factory->make(
                        ( $kname eq 'padav' ? 'ArrayLiteral' : 'HashLiteral' ),
                        inputs => [],
                        stamp  => SoN::IR::Stamp->new(
                            type => $kname eq 'padav' ? 'Array' : 'Hash' ));
                    $sim->define($targ, $empty);
                    $sim->push_node($empty);
                    return ($op->next, 'handled');
                }

                die "GAP: undef(EXPR) on this operand not yet lowered"
                  . " ($kname) -- on an aggregate it EMPTIES the container"
                  . " rather than rebinding a name, which is not `\@a = undef`\n"
                    unless $kname eq 'padsv' && $kid->targ;
                $undef_targ = $kid->targ;
                # The kid pushed nothing we want: this is a WRITE of the slot,
                # not a read of it.
                $sim->pop_node if $sim->stack_depth > 0;
            }
            my $node = _undef_constant($factory);
            if (defined $undef_targ) {
                $sim->define($undef_targ, $node);
                $sim->push_node($node);
                return ($op->next, 'handled');
            }
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

        # argelem -- a DECLARED SIGNATURE PARAMETER.
        #
        # This used to mint a PadAccess: perl's STORAGE for the parameter rather
        # than the parameter itself, discarding both the position and the sigil
        # that the op carries. A parameter is a VALUE identified by POSITION;
        # the pad slot is how perl happens to hold it.
        #
        # Everything needed is on the op, so nothing is inferred:
        #   aux_list($cv)  the positional INDEX  (0, 1, ...)
        #   private        the SIGIL             (0 scalar, 2 array, 4 hash)
        #   targ           the pad slot, still used to BIND the name
        #
        # The Parameter is bound into the pad slot exactly as before, so every
        # later read of $a resolves through $sim->define and sees the Parameter
        # instead of a PadAccess. Only the definition changes, not the lookup.
        if ($name eq 'argelem') {
            my $targ    = $op->targ;
            my $varname = _padname($cv, $targ);
            my ($index) = eval { $op->aux_list($cv) };
            $index = 0 unless defined $index;
            my %SIGIL   = (0 => '$', 2 => '@', 4 => '%');
            my $sigil   = $SIGIL{ $op->private // 0 } // '$';

            # STAMPED FROM THE SIGIL. `@a` is an Array, `%h` is a Hash --
            # containers, not the ArrayRef/HashRef REFERENCES that point at
            # them. A scalar parameter is left unstamped: its type comes from
            # the callsite, which this end cannot see.
            #
            # This block previously declined to stamp, on the grounds that the
            # lattice "has neither" Array nor Hash and that stamping one died
            # "Unknown stamp type". Both halves are now false: Stamp.pm carries
            # `Array => [List]` and `Hash => [List]`, and constructing either
            # succeeds. The comment outlived the condition it described.
            #
            # It stayed invisible because the failure it described was silent:
            # the die was swallowed by a bare eval in B::SoN, dropping the
            # whole sub from the wire with no diagnostic. Those evals now
            # report (B/SoN.pm), which is what makes stamping here safe to try
            # -- a mistake announces itself instead of deleting a sub.
            my %SIGIL_STAMP = ('@' => 'Array', '%' => 'Hash');
            my $stamp_type  = $SIGIL_STAMP{$sigil};
            my $node = $factory->make('Parameter',
                index => 0 + $index,
                name  => $varname,
                sigil => $sigil,
                ($stamp_type
                    ? (stamp => SoN::IR::Stamp->new(type => $stamp_type))
                    : ()),
            );
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
                    my $stamp = _result_stamp('Count', [$value]);
                    my %extra = defined $stamp ? (stamp => $stamp) : ();
                    $value = $factory->make('Count', inputs => [$value], %extra);
                }
                # A DEMOTED SLOT IS STORED, NOT BOUND. Its value lives in
                # memory because a reference to it exists, so the write is an
                # Assign(location, value) pinned to control and becoming the
                # new memory version -- the same store form the Subscript and
                # FieldAccess branches below use. Binding here instead would
                # let a later read resolve to the value and miss writes made
                # through the reference.
                if ($ctx->{addr_taken}{ $target->targ }) {
                    my $store = $factory->make('Assign',
                        inputs => [$target, $value]);
                    $store->set_control_in($sim->control);
                    $sim->set_control($store);
                    $sim->set_memory($store);
                    $sim->push_node($value);
                    return ($op->next, 'handled');
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
            # A STORE THROUGH A DEREFERENCE is the same shape: the target is a
            # location rather than a name, so the write is an Assign on the
            # memory chain and NOT a rebinding of the reference variable.
            #
            # It works because taking the reference already demoted the
            # referent -- `my $r = \$v` marks $v address-taken, so $v lives in
            # memory and its later reads carry a memory version. Storing
            # through $r writes that same location, which is what makes the
            # write visible to `print $v` and through any alias of $r.
            #
            # Binding instead would lose it silently: `$$r = 5` would rebind
            # nothing a later read of $v consults.
            elsif ($target->isa('SoN::IR::Node::Subscript')
                || $target->isa('SoN::IR::Node::PostfixDeref')) {
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
            # the target is a EntryDef lvalue. Without this branch the store
            # falls through to the catch-all below (push_node($value)), which
            # DROPS it -- a later `$g` read then loads an uninitialized slot (a
            # silent miscompile). Emit an explicit Assign(EntryDef-lvalue,
            # value) threaded onto the control chain via control_in, exactly
            # like the Subscript/FieldAccess element/field stores. Stamp the
            # lvalue EntryDef with the RHS value's OWN repr (Int for `= 5`,
            # Str for `= "hi"`) so the matching read carries the right type: the
            # store lvalue and the read hash-cons to ONE node, so stamping here
            # types both. A hardcoded Int would miscompile a Str global. Fall
            # back to Int when the RHS carries no stamp (the historical default).
            elsif ($target->isa('SoN::IR::Node::EntryDef')) {
                # An assignment is a DEFINITION, not a store into a cell: it
                # binds a new value that later reads of this name resolve to.
                # Identical to the PadAccess branch above -- the EntryDef was
                # pushed as a name token and never enters the dataflow.
                #
                # This replaces an Assign(EntryDef-lvalue, value) into a
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
            # A LITERAL LIST IS AN ARRAY OF KNOWN SIZE. `for my $i (1,2,3)`
            # does NOT set OPf_STACKED -- measured, it compiles to pushmark +
            # three consts + `enteriter vK/LVINTRO` with no S -- because there
            # is no range or aggregate to stack: the elements are simply pushed,
            # and pop_to_mark returns them.
            #
            # So wrap them in the ArrayRef the anonlist handler already builds
            # and hand them to the array path, which bounds by Count and reads
            # Subscript(arr, i). Nothing new is needed for the iteration itself.
            #
            # This was the most common GAP across perl's t/base, t/cmd and
            # t/comp -- 7 occurrences, more than any other.
            my $list_literal = 0;
            if (!($op->flags & 64)) {   # not OPf_STACKED
                $list_literal = 1;
            }
            # THE MARK CAN ALREADY BE SPENT. A mark-consuming builtin in the
            # loop's list expression takes it before the foreach reaches here:
            #
            #     foreach (unpack("W*",$s)) {}   pushmark -> unpack -> enteriter
            #
            # unpack pops to that mark to build its Call, so pop_to_mark then
            # died "No mark on mark stack" -- an INTERNAL ERROR masking what is
            # really an unlowered pairing (perl's own t/op/caller.t). The
            # list-assigned form `my @u = unpack(...)` has no such contention
            # and works, which is what places the defect in the pairing rather
            # than in unpack.
            die "GAP: a foreach over a mark-consuming builtin (its list"
              . " expression already spent the mark) is not yet lowered\n"
                unless $sim->has_mark;
            my $bounds = $sim->pop_to_mark;

            # THE ITERATOR IS A PAD SLOT OR A PACKAGE SCALAR, and the scope map
            # holds both -- it is a plain hash, keyed by pad targ for a lexical
            # and by `stash::$name` for a package variable, which is how every
            # other package-scalar read and write already resolves.
            #
            # A package iterator has NO targ, and its glob rides the stack:
            # rv2gv is OpMap SKIP, so pop_to_mark returns one element MORE than
            # a lexical loop does, with the name last. Measured:
            #
            #     foreach my $i (1..3)   Constant(1) | Constant(3)
            #     foreach $t     (1..3)  Constant(1) | Constant(3) | Constant(t)
            #
            # Split the name off HERE, before the shape check below counts
            # bounds -- otherwise the glob counts as a third bound and the loop
            # is misclassified as an unrecognized shape.
            my $iter_key = $op->targ;
            if (!$iter_key) {
                my $name_node = $bounds->@* > 2 ? pop $bounds->@* : undef;

                # AN IMPLICIT $_ ITERATOR IS MARKED ON THE OP, not recoverable
                # from the stack. perl sets OPpITER_DEF (private 0x8) --
                # measured 0x8 for `for (1..3)` and 0x0 for
                # `for $main::t (1..3)` -- and the name node that arrives for
                # the implicit form is NOT the iterator: resolving `gv[*_]`
                # yields an ArgsSource, because `$_` and `@_` share the glob
                # name `_`. That is the same sigil hazard the match handler
                # records, and it is why keying off the stack refused this.
                #
                # $_ keys exactly as the match and s/// handlers key it.
                if ($op->private & 8) {   # OPpITER_DEF
                    # The `gv[*_]` is always the LAST element, whatever the
                    # bounds count -- one for `for (@a)`, two for `for (1..3)`
                    # -- so it cannot be split off by arity the way a named
                    # package iterator's is. Drop it here, where OPpITER_DEF
                    # says it is there: left in place it is counted as a bound
                    # and `for (@a)` is misread as a two-element shape
                    # (measured: [ArrayRef, ArgsSource]).
                    pop $bounds->@* if !$name_node && $bounds->@* > 1;
                    $iter_key = 'main::$_';
                    goto ITER_KEYED;
                }

                die "GAP: foreach with an unnameable iterator not yet"
                  . " lowered\n"
                    unless $name_node
                        && $name_node->isa('SoN::IR::Node::Constant')
                        && defined $name_node->value;
                # KEYED EXACTLY AS _stash_key SPELLS IT -- stash, then '::',
                # then the SIGIL, then the name -- because the body's reads of
                # $t resolve through that same spelling. A near-miss here binds
                # the iterator under a name nothing looks up.
                my $stash = eval { $cv->GV->STASH->NAME } // 'main';
                $iter_key = $stash . '::$' . $name_node->value;
                ITER_KEYED: ;
            }
            # A LIST LITERAL: every popped value is an element. Wrap and take
            # the array path. Guarded on there being something to iterate --
            # `for () {}` has no elements and no loop to build.
            if ($list_literal) {
                die "GAP: foreach over an empty list not yet lowered\n"
                    unless $bounds->@*;
                my $arr = $factory->make('ArrayLiteral', inputs => [$bounds->@*]);
                _translate_foreach_array($cv, $op, $sim, $factory, $opmap,
                    $ctx->{visited}, $arr, $iter_key);
                return (($op->can('lastop') ? $op->lastop : $op->next),
                        'handled');
            }

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
                    $ctx->{visited}, $bounds->@*, $iter_key);
            }
            elsif ($bounds->@* == 1 && _is_aggregate_node($bounds->[0])) {
                _translate_foreach_array($cv, $op, $sim, $factory, $opmap,
                    $ctx->{visited}, $bounds->[0], $iter_key);
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
                    $ctx->{visited}, $bounds->[0], $iter_key);
            }
            else {
                die "GAP: foreach with unrecognized bounds shape not yet lowered\n";
            }
            # Continue after the loop; the B::LOOP op's lastop is leaveloop.
            return (($op->can('lastop') ? $op->lastop : $op->next), 'handled');
        }

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
                my $stamp = _result_stamp('Count', [$value]);
                my %extra = defined $stamp ? (stamp => $stamp) : ();
                $value = $factory->make('Count', inputs => [$value], %extra);
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
            # NO DEMOTION BRANCH HERE, deliberately. padsv_store is an rpeep
            # FUSION of (const, padsv, sassign), and this walker suppresses
            # rpeep (B::SoN.pm BEGIN) -- so in production a pad assignment
            # arrives as `sassign` and that handler owns the demoted-store
            # case. A copy here would be dead code that silently diverges.

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
            # STAMP IT HERE, do not lean on a class default. `[]` and `{}` are
            # always REFERENCES, but the ArrayRef/HashRef node CLASS is the
            # container constructor and carries either stamp: the list branch
            # below builds the same class for `my @a = (1,2,3)` and stamps it
            # Array, because an array is not a reference to one (the miscompile
            # recorded at the aggregate walk). A class-level default would be
            # right here and silently WRONG at the next unstamped list-branch
            # site, turning a loud missing-stamp death into a bad type.
            my $node = $factory->make($is_hash ? 'HashLiteral' : 'ArrayLiteral',
                inputs => [],
                stamp  => SoN::IR::Stamp->new(
                    type => $is_hash ? 'HashRef' : 'ArrayRef'));
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
            my $pop_count = _variadic_pop_count($op, $name)
                         // $opmap->pop_count($name);
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
                    %extra = (%extra, _sort_fields($op)) if $name eq 'sort';
                }
                my $stamp = ( $node_type eq 'Call'
                              ? _context_builtin_stamp($op, $name) : undef )
                         // _result_stamp($node_type, \@inputs,
                    $node_type eq 'Call' ? $name : undef);
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
            # target is a EntryDef keyed by its qualified name. %scope takes
            # either, which is the whole reason a package aggregate needs no
            # separate machinery -- `our` and `my` differ in visibility and
            # lifetime, not in modelling.
            #
            # The SIGIL says which container to build. A PadAccess carries it in
            # varname ('@a'); a EntryDef does not, so it comes from the op
            # that pushed the target -- rv2av for an array, rv2hv for a hash.
            if (@$lhs == 1 && $sim->has_mark
                && ( $lhs->[0]->isa('SoN::IR::Node::PadAccess')
                  || $lhs->[0]->isa('SoN::IR::Node::EntryDef') )) {
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

                    # AN AGGREGATE RHS IS THE VALUE, NOT AN ELEMENT OF ONE. The
                    # wrap below makes each popped value one ELEMENT, which is
                    # right for `my @a = (1,2,3)` -- three inputs, Count reads 3.
                    # But a single value that is ALREADY the aggregate being
                    # assigned (what map/grep produce: an accumulated Array)
                    # would become ArrayLiteral[Array] -- ONE input holding TWO
                    # elements -- and a consumer counting inputs reads 1 where
                    # perl says 2. Match on the STAMP, not the node kind: an
                    # ArrayLiteral is itself an aggregate node, so keying off
                    # that would stop wrapping `my @a = (@b)` legitimately.
                    # A BUILTIN THAT YIELDS N VALUES IS ALSO ALREADY THE
                    # AGGREGATE. Keying only on the stamp fires for a value
                    # (`my @a = @b`, stamped Array) and walks past a CALL,
                    # which is stamped Unknown -- so `my @k = keys %h` became
                    # ArrayLiteral[Call], one input for two elements, and
                    # Count read 1 where perl says 2.
                    #
                    # The discriminating property is whether the operand
                    # yields N values, not what it is stamped; the stamp is a
                    # proxy that does not hold for a Call. Same error as the
                    # map/grep contribution deny-list, one construct over.
                    state $YIELDS_LIST = { map { $_ => 1 }
                        qw( keys values sort reverse map grep splice ) };

                    my $want = $sigil eq '@' ? 'Array' : 'Hash';
                    if ($rhs->@* == 1) {
                        my $only  = $rhs->[0];
                        my $stamp = $only->stamp;
                        my $is_aggregate_value =
                            defined $stamp && $stamp->type eq $want;
                        my $is_list_builtin =
                               $only->operation eq 'Call'
                            && $only->can('name')
                            && defined $only->name
                            && $YIELDS_LIST->{ $only->name };

                        if ($is_aggregate_value || $is_list_builtin) {
                            $sim->define($key, $only);
                            $sim->push_node($only);
                            return ($op->next, 'handled');
                        }
                    }
                    # AN ARRAY IS NOT A REFERENCE TO ONE. The node KIND is the
                    # container constructor (there is one per aggregate kind);
                    # the STAMP says what the value IS, and the sigil above
                    # already proved it. `my @a=(1,2,3)` is an Array (List
                    # branch); `my $r=[1,2,3]` is an ArrayRef (Ref branch).
                    # Defaulting both to the Ref member made them
                    # indistinguishable downstream and forced
                    # _rhs_is_aggregate_access to key scalar context on the OP
                    # rather than the repr.
                    my $node = $factory->make(
                        ($sigil eq '@' ? 'ArrayLiteral' : 'HashLiteral'),
                        inputs => [$rhs->@*],
                        stamp  => SoN::IR::Stamp->new(
                            type => ($sigil eq '@' ? 'Array' : 'Hash')));
                    $sim->define($key, $node);
                    $sim->push_node($node);
                    return ($op->next, 'handled');
                }
            }

            # Fallback: a generic list assignment. THE RHS IS STILL ON THE
            # STACK behind its mark, and building the Assign from the LHS alone
            # DROPPED IT -- measured:
            #
            #     @_ = map { "x$_" } "y";  print "@_";
            #     perl:  xy
            #     graph: Assign in=[ArgsSource]   -- one input, no value
            #
            # The map result reached nothing, so a consumer could not recover
            # what was assigned. The Unknown stamp was the SYMPTOM: a 1-input
            # Assign has no stored value to yield, which _derived_type honestly
            # refuses. Stamping it without taking the RHS would have papered
            # over a silent drop.
            # TAKE ONLY WHAT IS ABOVE THE MARK, and do NOT consume the mark
            # itself: it may belong to an enclosing construct, and popping it
            # left a later handler with none ("No mark on mark stack" in
            # comp/require.t's bytes_to_utf, which is an INTERNAL error rather
            # than an honest GAP).
            my @rhs;
            unshift @rhs, $sim->pop_node
                while $sim->stack_depth > $sim->mark_depth;
            my $node = $factory->make('Assign',
                inputs => [ $lhs->@*, @rhs ]);
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
            # AN EXPLICIT FILEHANDLE IS STATED, NOT REFUSED. This used to
            # GAP because "the runtime-free backend writes only to stdout, so
            # honoring a handle would misroute" -- which is a T2 judgement
            # (can this TARGET represent a filehandle) made inside T1, whose
            # job is to say truthfully what the program DOES. The producer
            # names the operation; the consumer decides whether it can lower
            # it, and refuses there if it cannot.
            #
            # OPf_STACKED means an rv2gv pushed the handle BEFORE the args, and
            # rv2gv is OpMap SKIP, so the handle node is already on the stack
            # under them. pop_to_mark takes the whole run, handle included, and
            # it is first -- which is the order print itself uses.
            my $has_fh = ($op->flags & 64) ? 1 : 0;
            my $args = $sim->pop_to_mark;
            my @inputs = $args->@*;

            # The newline is appended as an ordinary Str operand, so a `say`
            # lowers through exactly the same path a `print LIST, "\n"` does.
            # It goes after the ARGUMENTS, and the handle stays at operand 0.
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
            #
            # THE FILEHANDLE IS NOT AN ARGUMENT. It is operand 0 when
            # OPf_STACKED is set, it is a destination rather than something to
            # print, and stringifying it is wrong in kind: `print STDERR "x"`
            # writes "x" to stderr, it does not write "STDERR". This was masked
            # while the gv handler stamped the handle Str -- _coerce_to_str
            # returns a Str operand unchanged, so the wrong rule and the wrong
            # operand type cancelled. Once the handle became an honest Glob the
            # coercion fired and Coerce(Glob->Str) displaced the handle at
            # operand 0.
            my $fh_operand = $has_fh ? shift @inputs : undef;
            @inputs = map {
                my $st = $_->can('stamp') ? $_->stamp : undef;
                defined $st ? _coerce_to_str($factory, $_) : $_;
            } @inputs;
            unshift @inputs, $fh_operand if defined $fh_operand;

            # Void statement position (the only shape wired): control-pin via
            # control_in (produce-time control) so the stdout effect is
            # ordered and survives DCE, mirroring the I1 void-effect path.
            my $is_effect = defined $sim->control;
            # STAMPED, because print HAS a return value and this file already
            # said so twice in prose -- Print.pm's ABOUTME ("yielding print's
            # boolean 1") and the push below ("print returns 1") -- while
            # leaving the node untyped, so a sub whose body ends in print had
            # nothing to derive a return type from and declared Unknown.
            #
            # Measured: `print ""` yields 1; printing to a read-only handle
            # yields undef. So the honest type is join(Boolean,Undef), which
            # the lattice puts at Scalar -- the same derivation `open` and
            # `binmode` use. Boolean ALONE would be wrong rather than narrow,
            # since Boolean does not admit undef.
            my $node = $factory->make('Print', inputs => \@inputs,
                has_filehandle => $has_fh,
                stamp => SoN::IR::Stamp->new(type => 'Scalar'));
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
            my $pop_count = _variadic_pop_count($op, $name)
                         // $opmap->pop_count($name);
            my $node_type = $opmap->node_type($name);
            my $push_count = $opmap->push_count($name);

            # REFUSE BEFORE POPPING. A GAP op still carries a pop_count from the
            # table, so popping first UNDERFLOWED the stack and died with "Stack
            # underflow at StackSim.pm line 25" -- an internal error raised a few
            # lines above the GAP that would have named the construct. Measured
            # on `goto FOO; print "x"`: goto is pop_count=1, node_type=undef, so
            # it popped an operand it does not have and the reader was sent after
            # a simulator bug instead of an unlowered `goto`. Same shape that hid
            # block eval behind an underflow.
            die $UNBUILT_OP_GAP{$name} . "\n"
                if exists $UNBUILT_OP_GAP{$name};

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
                    %extra = (%extra, _sort_fields($op)) if $name eq 'sort';
                }

                # A BAREWORD FILEHANDLE IS A GLOB, NOT ITS NAME. `open(FOO,...)`
                # reaches here with operand 0 a Str Constant "FOO" -- the gv
                # handler's name-as-string, correct for naming a callee and a
                # fabrication here, the same defect `\*STDOUT` had. Unlike that
                # one there is no rv2gv to key on: measured, the optree hands
                # the gv straight to the builtin
                #
                #     open(FOO,...)   gv[*FOO] -> const -> open    no rv2gv
                #     close FOO       gv[*FOO] -> close            no rv2gv
                #     print FOO "x"   gv[*FOO] -> rv2gv -> print   rv2gv
                #
                # and `$op->next` is the next ARGUMENT for the variadic forms,
                # so it cannot identify the consumer either. The builtin's own
                # name is the reliable signal, and it is in hand right here.
                #
                # GLOB, NOT GlobRef, and the distinction is perl's:
                #
                #     ref(*FOO)   not a reference at all -- a Glob
                #     ref(\*FOO)  GLOB                   -- a GlobRef
                #     ref($lex)   GLOB                   -- a GlobRef
                #
                # A bareword IS the glob; a lexical handle HOLDS a reference to
                # one. join(Glob, GlobRef) is Unknown, so these are genuinely
                # two types and one requirement cannot cover both -- which is
                # why this is stamped at the operand rather than declared as an
                # `operands` entry. Declaring GlobRef there made the coercion
                # pass insert Coerce(Str -> GlobRef), fabricating a filehandle
                # out of the string "FOO".
                if ($node_type eq 'Call' && $IO_HANDLE_BUILTIN{$name}
                    && @inputs
                    && $inputs[0]->isa('SoN::IR::Node::Constant')
                    && ($inputs[0]->const_type // '') eq 'string'
                    && $inputs[0]->stamp
                    && $inputs[0]->stamp->type eq 'Str') {
                    $inputs[0] = $factory->make('Constant',
                        value      => $inputs[0]->value,
                        const_type => 'glob',
                        stamp      => SoN::IR::Stamp->new(type => 'Glob'));
                }

                # A LEXICAL HANDLE IS DEFINED BY THE OPEN ITSELF. `open(my $T,
                # ...)` passes an unstamped PadAccess, and nothing downstream
                # can type it: the slot's value is created BY this call.
                # Measured on 5.42.0, after the open
                #
                #     ref($T)      GLOB     so the type is GlobRef
                #     blessed($T)  no       not an object, so not IO
                #
                # AND OPEN DEFINES IT EVEN WHEN THE OPEN FAILS:
                #
                #     open($T,"<","/nonexistent")  false, but $T is ref GLOB
                #
                # so the stamp is unconditional rather than join(GlobRef,Undef).
                # Only `open` does this -- close/readline READ a handle someone
                # else defined, so stamping there would be inventing a type for
                # a value this call did not create.
                #
                # NOT DECLARED AS AN `operands` REQUIREMENT, because a bareword
                # handle is a Glob and a lexical one is a GlobRef -- two types
                # with no common parent (join is Unknown). A GlobRef
                # requirement made the coercion pass wrap the bareword in
                # Coerce(Glob -> GlobRef), fabricating a reference from a glob
                # that is not one.
                if ($node_type eq 'Call' && $name eq 'open'
                    && @inputs
                    && $inputs[0]->isa('SoN::IR::Node::PadAccess')
                    && (!$inputs[0]->stamp
                        || $inputs[0]->stamp->type eq 'Unknown')) {
                    $inputs[0]->set_stamp(
                        SoN::IR::Stamp->new(type => 'GlobRef'))
                        if $inputs[0]->can('set_stamp');
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
                    # NO FLOOR HERE. The array's own element type is the
                    # better answer and belongs at construction time
                    # (`my @q=(1,2,3); shift @q` is Int). Where it declines,
                    # the builtin index's `Scalar` still holds -- but stamping
                    # it HERE would be a floor laid before any narrowing pass
                    # runs, which is the ordering _floor_element_removals
                    # exists to get right. It is applied there, after the
                    # fixpoint, and this leaves the node honestly unstamped.
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
                # A COMPARISON IS NEVER A COMPOUND ASSIGNMENT. This test
                # recognises the `OP=` family -- `+=`, `-=`, `.=`, `||=` -- each
                # of which reads the variable, applies a binary operator, and
                # WRITES THE RESULT BACK, which is why it rebinds below.
                # Comparisons have no member in that family: there is no
                # spelling that means "compare and store the answer into the
                # left operand". `ne`/`lt`/`==` read both operands and yield a
                # Boolean, leaving the variable alone. But perl leaves OPf_MOD
                # set on a comparison's first operand after folding a dead arm
                # (`if (0) {...} elsif ($x != $y)`), which satisfied every other
                # clause of this test -- so the comparison was taken for a
                # read-modify-write and $x was REBOUND to the Boolean below.
                #
                # Inside a loop that is a silent miscompile: the body's
                # `$i + 1` then read the comparison instead of the counter, and
                # `for my $i (0..2) { ...; print $i + 1 }` printed 111 where perl
                # prints 123. Found in perl's own t/base/translate.t.
                # THE OPTREE DECIDES THIS, NOT THE STACK. Testing
                # `$inputs[0]->isa('PadAccess')` asked whether the lvalue read
                # SURVIVED to the top of the stack, which is a different
                # question from whether this op is a compound assignment -- and
                # the two answers diverge as soon as the RHS contains a branch.
                #
                # `$s += ($i > 1 ? 10 : 1)` walks its ternary through
                # _handle_cond_expr, which snapshots the sim per arm; by the
                # time the add pops its operands, $s's PadAccess has already
                # been resolved to its bound value, so inputs[0] is a Constant:
                #
                #     $s += 1              inputs=[PadAccess, Constant]     rebound
                #     $s += ($c ? 10 : 1)  inputs=[Constant, TernaryExpr]   NOT rebound
                #
                # Both optrees say the same thing -- `add` with OPf_STACKED,
                # first=padsv carrying OPf_MOD -- so the optree is the stable
                # signal and the stack is not.
                #
                # WITHOUT THE WRITE-BACK THE MUTATION VANISHES, and it fails
                # silently. `$s` is never rebound, so the loop scout (which
                # discovers loop-carried slots by looking for rebinds) does not
                # see it, no header Phi is created, and the accumulator reads
                # its PRE-LOOP binding forever. The add itself is then consumed
                # by nothing. Measured on chalk's corpus control-flow.md T3
                # (`while ($i<3) { $s += ($i>1 ? 10 : 1); $i++ }`): perl prints
                # 12, the emitted program printed 0 -- a WRONG ANSWER, not a
                # refusal, which is the worst failure mode this producer has.
                #
                # OPf_STACKED (0x40) IS THE `op=` MARKER and it is what keeps
                # this from over-firing. Measured:
                #
                #     $y = $x + 2   add[$y:2,3] vK/TARGMY,2   no STACKED
                #     $s += 1       add[t2]     vKS/2         STACKED
                #
                # A plain binary op that happens to read an OPf_MOD operand has
                # no STACKED, so it is not taken for a read-modify-write. The
                # comparison guard stays: perl leaves OPf_MOD set on a
                # comparison's first operand after folding a dead arm, and
                # rebinding $x to a Boolean there made `for my $i (0..2)` print
                # 111 for 123 in perl's own t/base/translate.t.
                my $is_compound =
                       @inputs >= 1
                    && !_is_comparison_optree_op($op->name)
                    && $op->can('first')
                    && $op->first->name =~ /^padsv|^padav|^padhv/
                    && ($op->first->flags & 32)   # OPf_MOD
                    && ( $inputs[0]->isa('SoN::IR::Node::PadAccess')
                         # OPf_STACKED (the `op=` form) recovers the case where
                         # the lvalue PadAccess did not survive the stack. It
                         # must NOT claim a class field: `$n += 1` in a method
                         # also reads an OPf_MOD padsv and is also STACKED, but
                         # its value lives in the object struct and needs the
                         # field-store Assign that $field_compound emits below.
                         # Without this exclusion a pad rebind silently replaced
                         # that store and the field mutation was dropped.
                         || (   ($op->flags & 64)
                             && !$inputs[0]->isa('SoN::IR::Node::FieldAccess') ) );

                my $lvalue_targ;
                if ($is_compound) {
                    # The targ comes from the OPTREE when the PadAccess did not
                    # survive: $inputs[0]->targ is unavailable precisely in the
                    # branch-RHS case this fix exists for.
                    $lvalue_targ = $inputs[0]->isa('SoN::IR::Node::PadAccess')
                        ? $inputs[0]->targ
                        : $op->first->targ;
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

                my $stamp = ( $node_type eq 'Call'
                              ? _context_builtin_stamp($op, $name) : undef )
                         // _result_stamp($node_type, \@inputs,
                    $node_type eq 'Call' ? $name : undef);

                # AN ANON-REF LITERAL IS A REFERENCE, and only the OPTREE OP
                # knows it. `anonlist`/`anonhash` build the SAME ArrayRef /
                # HashRef node class as the aggregate walk's sigil branch, which
                # stamps Array/Hash for `my @a = (1,2,3)` -- an array is not a
                # reference to one (the miscompile recorded at that branch). The
                # fact belongs to the OP, not the class: a class-level
                # default_stamp_type would be right here and silently WRONG
                # there, which is why ArrayRef/HashRef declare none.
                if ($name eq 'anonlist' || $name eq 'anonhash') {
                    $stamp = SoN::IR::Stamp->new(
                        type => $name eq 'anonlist' ? 'ArrayRef' : 'HashRef');
                }

                # BACKTICKS ARE CONTEXT-SENSITIVE, so they cannot be a
                # TypeLibrary result: `my $x = \`cmd\`` yields one Str, while
                # `my @x = \`cmd\`` yields the output split into lines. perl
                # marks the difference on the op (sK vs lK) and ONE
                # BacktickExpr node serves both -- list context wraps it in an
                # ArrayRef afterwards. A fixed Str rule would be wrong for the
                # list form, so read the context here where the op is in hand.
                if ($node_type eq 'BacktickExpr') {
                    my $want = $op->flags & 3;   # OPf_WANT
                    $stamp = SoN::IR::Stamp->new(
                        type => $want == 3 ? 'List' : 'Str');   # 3 = LIST
                }

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
            elsif (exists $UNBUILT_OP_GAP{$name}) {
                # This op builds no node AND nothing else compiles the construct
                # it belongs to, so continuing would drop it silently. Refuse by
                # name instead.
                #
                # Keyed by an explicit list rather than inferred from "undef
                # node_type and no SKIP flag": that shape ALSO covers ops which
                # correctly build nothing because a structural handler owns the
                # construct (poptry, leavetry, the method_* family). Treating
                # the table's shape as a semantic fact conflates the two.
                die $UNBUILT_OP_GAP{$name} . "\n";
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
    # _and_is_loop_back_edge($and_op) -- is this and/or the CONDITION of a
    # postfix-while rather than a statement modifier?
    #
    # Both spell the same op. The loop's body arm ends in an `unstack` whose
    # ->next jumps BACKWARD to the condition head; a modifier's arm runs
    # forward to the join. _is_postfix_while asks this from the `enter` that
    # precedes the condition, which is where the main walk meets the construct
    # -- but a walk that starts INSIDE an if/else arm meets the `and` first and
    # has no enter to ask about.
    # _loop_cond_head($and_op) -- the op a postfix-while's back-edge returns to,
    # which is the loop's condition head and what _translate_while_loop expects.
    # It is exactly the unstack's ->next: perl's back-edge jumps to the first op
    # of the condition, so the loop tells us where it begins.
    sub _loop_cond_head ($op) {
        return undef unless $op->can('other') && ${ $op->other };
        my $arm = $op->other;
        my %seen;
        while ($$arm && !$seen{$$arm}++) {
            if ($arm->name eq 'unstack') {
                my $target = $arm->next;
                return ( ref($target) && $$target ) ? $target : undef;
            }
            last if $arm->name eq 'leave' || $arm->name eq 'nextstate';
            $arm = $arm->next;
        }
        return undef;
    }

    # _restore_locals($sim, $ctx) -- put back every binding a `local` in this
    # scope replaced.
    #
    # Under SSA a package variable IS its binding, so the restore is a rebind:
    # the node that was bound before the `local` goes back into the scope map,
    # and reads after the scope resolve to it. Nothing is written to memory
    # because nothing was read from it.
    #
    # LIFO, because `local` nests: the innermost save is the most recent, and
    # restoring in reverse gives each scope the binding its own entry saw.
    sub _restore_locals ($sim, $ctx) {
        my $saves = $ctx->{local_saves} or return;
        while (my $save = pop $saves->@*) {
            # A `local` on a name with NO prior binding leaves the name unbound
            # rather than bound to undef -- define() cannot express that, so the
            # binding is simply left as the local set it. Measured as rare and
            # not what rs.t does (`local @INC` has an @INC to restore).
            $sim->define($save->{key}, $save->{node}) if defined $save->{node};
        }
    }

    sub _and_is_loop_back_edge ($op, $cond_head = undef) {
        return 0 unless $op->can('other') && ${ $op->other };
        $cond_head //= $op;
        my $arm = $op->other;
        my %seen;
        while ($$arm && !$seen{$$arm}++) {
            if ($arm->name eq 'unstack') {
                # A BACK-EDGE IS AN OP WE HAVE ALREADY WALKED PAST, and the
                # only reliable way to say so is to look for the target on the
                # path from the condition head to this and/or. Comparing op
                # ADDRESSES does not work -- they are allocation order, not
                # execution order (measured: the target of a real back-edge
                # compared HIGHER than the and).
                my $target = $arm->next;
                return 0 unless $$target;
                my $p = $cond_head;
                my %pseen;
                while ($$p && !$pseen{$$p}++) {
                    return 1 if $$p == $$target;
                    last if $$p == $$op;
                    $p = $p->next;
                }
                return 0;
            }
            last if $arm->name eq 'leave' || $arm->name eq 'nextstate';
            $arm = $arm->next;
        }
        return 0;
    }

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
    sub _body_writes_targ ($cv, $start_op, $sim, $opmap, $targ, $cond_consumed = 0) {
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
        _walk_loop_body($cv, $start_op, $scout_sim, $scout_factory, $opmap, {}, {},
            undef, undef, $cond_consumed);
        my $after = $scout_sim->scope_bindings->{$targ};
        return defined $after && $after != $ph;
    }

    sub _scout_mutated_targs ($cv, $start_op, $sim, $opmap, $extra_targs = [], $cond_consumed = 0) {
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
        _walk_loop_body($cv, $start_op, $scout_sim, $scout_factory, $opmap, {}, {},
            undef, undef, $cond_consumed);
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
            (_is_narrowed($init->stamp) ? (stamp => $init->stamp) : ()));
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
    # STRING comparison on ids, not numeric. A node id is a string --
    # "Phi#unique4", "Subscript|ArrayRef#2|Phi#unique4|MemStart",
    # "Constant|const_type=integer|value=1" -- and every one of them numifies to
    # 0, so `==` reported ANY pair of nodes as the same node. Both guards below
    # inverted:
    #
    #   the `grep` matched any input, so "consumes the Phi directly" never
    #   rejected; the `next if` skipped every input, so the loop body -- the
    #   check that an unstamped input must be a deferred element read -- never
    #   ran at all.
    #
    # This predicate is the ONLY thing standing between an unstamped back-edge
    # and _patch_loop_phi keeping the Phi's init stamp, so returning true
    # unconditionally made the `die "GAP: loop-carried value loses its stamp"`
    # below it unreachable through this path, and let a Phi keep a stamp it had
    # not earned. See t/from-optree-phi-identity.t.
    my %_ARITH_OP = map { $_ => 1 } qw(Add Subtract Multiply Divide Modulo);
    sub _backedge_is_phi_recurrence ($post, $phi) {
        return false unless blessed($post) && $_ARITH_OP{$post->operation};
        my @ins = $post->inputs->@*;
        my $reads_phi = grep { blessed($_) && $_->id eq $phi->id } @ins;
        return false unless $reads_phi;
        for my $in (@ins) {
            next unless blessed($in);
            next if _is_narrowed($in->stamp);            # already narrowed
            next if $in->id eq $phi->id;                # the recurrence arm
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
    # True when a stamp says something -- when it has been narrowed below the
    # lattice top. Every Value node carries a stamp now, so defined-ness no
    # longer distinguishes "known" from "unknown": `Unknown` IS the top, and
    # means nothing has narrowed this value yet. Code that used to ask
    # `defined $node->stamp` to mean "do we know anything here" must ask this
    # instead; the old question now answers yes for everything.
    #
    # Named for NARROWING rather than for typedness on purpose. A stamp is an
    # abstract-interpretation fact ABOUT a value (C2's and Graal's sense), of
    # which the type is one component -- Graal's also carry non-null, exact
    # type, and integer ranges, filled in by refinement passes that narrow a
    # stamp along a branch. This compiler has no such passes yet, so `type` is
    # currently the only component and testing it is the whole question. When
    # refinement lands, a stamp will be able to be informative while its type
    # is still Unknown, and the check widens here rather than at every caller.
    sub _is_narrowed ($stamp) {
        return defined $stamp && $stamp->type ne 'Unknown';
    }

    sub _patch_loop_phi ($sim, $targ, $phi, $post) {
        $phi->set_backedge($post);
        $sim->define($targ, $phi);
        my $init = $phi->inputs->[0];
        # "Has a stamp" is not the question -- every Value node carries one
        # now. The question is whether it says anything, and `Unknown` is how
        # a stamp says it does not. Testing defined-ness alone would route an
        # untyped back-edge into the widening check below, where
        # join(Int, Unknown) is Unknown and the mismatch reads as a widening
        # that needs a fixpoint re-walk. It is not one: it is the deferred
        # case the elsif branch already handles.
        if (_is_narrowed($init->stamp) && _is_narrowed($post->stamp)) {
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
        # A LOOP MAY EXIT BY ITS BREAK ALONE. `while (1) { ... last if C }` has
        # NO header test -- perl folds the constant condition away entirely, so
        # `enterloop` carries no condition op and the `last` is the only way
        # out. Requiring a header exit refused the idiom outright: perl's own
        # t/base/while.t tests it second, and the whole file compiled to an
        # empty `methods` object.
        #
        # The machinery below already handles this. Phase 5 builds the exit
        # Region from `($exit_proj, @break_projs)` and gives every slot that
        # differs at the break its own exit Phi; a break-only loop is just that
        # list with nothing in the first position. So the requirement is not
        # "there is a header exit" but "there is SOME exit".
        #
        # A LOOP WITH NEITHER STILL GAPS, and that is the part worth keeping:
        # `while (1) { $x = $x + 1 }` never terminates, and refusing it is the
        # honest answer rather than emitting a graph whose exit Region has no
        # predecessors.
        die "GAP: loop without a lowerable condition\n"
            unless defined $exit_proj || @break_projs;

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
        # grep defined: a break-only loop has no header exit to lead with.
        my @exit_preds = grep { defined }
            ($exit_proj, map { $_->{proj} } @break_projs);
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
                    (_is_narrowed($header->stamp) ? (stamp => $header->stamp) : ()));
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
    # $iter_key names the iteration variable in the scope map: a pad targ for a
    # lexical, `stash::$name` for a package scalar. Defaults to the op's targ so
    # existing callers are unchanged.
    sub _translate_foreach_range ($cv, $enteriter, $sim, $factory, $opmap, $visited, $low, $high, $iter_key = undef) {
        my $i_targ = $iter_key // $enteriter->targ;

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
        my $mutated = _scout_mutated_targs($cv, $body_start, $sim, $opmap, [$i_targ], 1);

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

        # A foreach has no and/or loop condition of its own (the range iterator
        # drives it, and its iteration `and` was consumed at $and_op above), so
        # every top-level and/or in the body is a GUARD -- an else-less `if` or a
        # postfix modifier. The body walk is told so ($cond_consumed = 1 below)
        # and splits each one into a real If rather than mistaking the first for
        # a loop condition, which would drop the guard and fire the guarded
        # statement every iteration (`$s=$s+$i unless $i==2` over 1..3 gave 106,
        # not 104, zhi 019f5a27).

        # Phase 3: body under Proj(loop,0); exit on Proj(loop,1).
        my $body_proj = $factory->make_cfg('Proj', inputs => [$loop_node], index => 0);
        my $exit_proj = $factory->make_cfg('Proj', inputs => [$loop_node], index => 1);
        $sim->set_control($body_proj);
        _walk_loop_body($cv, $body_start, $sim, $factory, $opmap, {}, $visited,
            undef, undef, 1);

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
    # $iter_key names the iteration variable in the scope map, as in the range
    # form: a pad targ for a lexical, `main::$_` for the implicit form, which
    # has no targ at all. Defaults to the op's targ so existing callers stand.
    # $body_start overrides where the body begins, and $collect asks for a
    # ListAppend accumulator. Both exist for map/grep, which are loops with the
    # same counted shape but a DIFFERENT body location (mapwhile/grepwhile
    # rather than enteriter/iter/and) and an output whose length is not the
    # input's. Defaulted, so a plain foreach is unchanged.
    sub _translate_foreach_array ($cv, $enteriter, $sim, $factory, $opmap, $visited, $array, $iter_key = undef, $body_start = undef, $collect = undef, $collect_op = undef) {
        my $x_targ = $iter_key // $enteriter->targ;

        # Locate the body (enteriter->next: unstack, iter, then the and whose
        # other-branch is the body) -- identical structure to the range form.
        if (!defined $body_start) {
            my $it = $enteriter->next;
            $it = $it->next while $$it && $it->name ne 'iter';
            die "GAP: foreach without an iter op\n" unless $$it;
            my $and_op = $it->next;
            die "GAP: foreach without an and condition\n"
                unless $$and_op && $and_op->name eq 'and';
            $body_start = $and_op->other;
        }

        # A body guard (an else-less `if` or a postfix `STMT if C`) splits into a
        # real If during the body walk, exactly as in the range form: this
        # foreach's iteration `and` is consumed just above, so $cond_consumed
        # tells the walk that every remaining top-level and/or is a guard.

        # ALIASING: Perl's `for my $x (@a)` ALIASES $x to each element, so a body
        # write `$x = ...` MUTATES @a in place. This lowering binds $x to a
        # READ-ONLY Subscript(arr, i) element copy, so a write to $x would NOT
        # propagate back to @a -- a silent miscompile (`for my $x (@a){ $x=$x+1 }
        # $a[0]` would read the un-incremented element). Detect an iterator write
        # by scouting WITHOUT excluding $x_targ: if $x is in the mutated set, the
        # body assigns the alias. GAP loudly until the write-back is modeled.
        die "GAP: foreach body writes the iterator variable (aliasing write-back "
          . "to the array) not yet lowered\n"
            if _body_writes_targ($cv, $body_start, $sim, $opmap, $x_targ, 1);

        # The loop bound is the array's element count.
        my $len = $factory->make('Count',
            inputs => [$array],
            stamp  => SoN::IR::Stamp->new(type => 'Int'));
        my $zero = $factory->make('Constant',
            value => 0, const_type => 'integer',
            stamp => SoN::IR::Stamp->new(type => 'Int'));
        my $elem_stamp = _array_element_stamp($array);

        # Phase 1: scout the body. $x rides on enteriter (its own slot) and gets
        # the element binding, not a carried-value Phi, so exclude it.
        my $pre_scope = $sim->scope_bindings;
        my $mutated = _scout_mutated_targs($cv, $body_start, $sim, $opmap, [$x_targ], 1);

        # Phase 2: header -- induction Phi (i: 0..len-1) plus one Phi per mutated
        # slot. The induction Phi is NOT bound to $x; $x is the element read below.
        my $loop_node = $factory->make_cfg('Loop', inputs => [$sim->control]);
        $sim->set_control($loop_node);
        my $i_phi = _make_loop_phi($factory, $loop_node, $zero);

        # $collect (map/grep) carries a LIST across the back-edge as well as the
        # induction variable. It is seeded with the empty list and grows by a
        # ListAppend per iteration -- see that node for why the output length is
        # not the input's.
        my $acc_phi;
        if ($collect) {
            my $empty = $factory->make('ArrayLiteral',
                inputs => [],
                stamp  => SoN::IR::Stamp->new(type => 'Array'));
            $acc_phi = _make_loop_phi($factory, $loop_node, $empty);
        }

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
        my $depth_before = $sim->stack_depth;
        _walk_loop_body($cv, $body_start, $sim, $factory, $opmap, {}, $visited,
            undef, undef, 1);

        # What the body left on the stack IS this iteration's contribution: for
        # map the body's value(s), for grep the PREDICATE -- in which case what
        # gets appended is the element, gated by that predicate.
        my $acc_next = $acc_phi;
        if ($collect) {
            my @produced;
            unshift @produced, $sim->pop_node
                while $sim->stack_depth > $depth_before;
            if ($collect eq 'grep') {
                die "GAP: grep block did not produce a single predicate value\n"
                    unless @produced == 1;
                $acc_next = $factory->make('ListAppend',
                    inputs => [$acc_phi, $elem, $produced[0]],
                    stamp  => SoN::IR::Stamp->new(type => 'Array'));
            }
            else {
                # THE CONTRIBUTION IS DECIDED, NOT INHERITED. The body runs in
                # LIST context (measured: `map { wantarray } (1)` yields LIST),
                # so an aggregate left on the stack contributes ALL of its
                # elements, not itself:
                #
                #     my %h=(a=>1,b=>2); map { %h } (1)   -> 4 elements
                #     my @b=(7,8);       map { @b } (1,2) -> 4 elements
                #
                # The array form flattens here already -- the walk pops its
                # elements individually. A HASH does not: it arrives as one
                # HashLiteral, and appending that container made a consumer
                # counting inputs read 1 where perl says 4. Refuse instead:
                # the pair count is a runtime property of the hash, so there
                # is no honest static arity to append, and a wrong count is
                # worse than a GAP.
                # AN ALLOW-LIST, BECAUSE THE PROPERTY IS ARITY, NOT IDENTITY.
                # The body runs in LIST context, so a contribution yielding N
                # values must arrive as N inputs; appending one node that
                # STANDS FOR N makes a consumer counting inputs read 1.
                #
                # This was twice keyed on the wrong property, and each proxy
                # was silently incomplete:
                #
                #   stamp (Hash/Array)  -- missed Slice, which is Unknown
                #   node kind (+Slice)  -- missed reverse/sort, which are Calls
                #
                # Every member is just "contributes != 1". Enumerating the
                # kinds that DO flatten is open-ended and fails silently as new
                # ones appear; enumerating the kinds KNOWN to yield exactly one
                # fails safe -- an unfamiliar shape becomes a GAP, not a wrong
                # count. The cost is refusing shapes that would have been fine.
                #
                # grep never reaches here (it returns above): its body is a
                # predicate read in boolean context, so its contribution is
                # 0-or-1 whatever the body evaluates to, and refusing it would
                # turn correct code into a false GAP.
                # Derived from the actual node set, not recalled: every op
                # whose result is one scalar value. Omissions are safe (they
                # refuse); inventions are not (a name that matches nothing
                # silently drops a real op out of the list), so this was built
                # by enumerating lib/SoN/IR/Node/*.pm rather than from memory.
                state $YIELDS_ONE_VALUE = { map { $_ => 1 } qw(
                    Add          And          AnonSub      BitAnd
                    BitOr
                    BitXor       Coerce       Complement   Concat
                    Constant     Count        Defined      DefinedOr
                    Divide       EnvRead      FieldAccess  Interpolate
                    IsaOp        Length       LeftShift    Match
                    Modulo       Multiply     Negate       Not
                    NotMatch     NumCmp       NumEq        NumGe
                    NumGt        NumLe        NumLt        NumNe
                    Or           PadAccess    Phi          Power
                    Ref          RefType      RegexCapture RegexMatch
                    RegexSubst   Repeat       RightShift   StrCmp
                    StrEq        StrGe        StrGt        StrLe
                    StrLt        StrNe        StructFieldAccess
                    StructRef    Subscript    Subtract     TernaryExpr
                    UnaryPlus    Xor
                ) };
                for my $c (@produced) {
                    next if $YIELDS_ONE_VALUE->{ $c->operation };
                    die "GAP: $collect body contribution of unknown arity"
                      . " (a " . $c->operation . " may yield more than one"
                      . " value, and appending it whole would count 1 where"
                      . " perl counts N) not yet lowered\n";
                }
                $acc_next = $factory->make('ListAppend',
                    inputs => [$acc_phi, @produced],
                    stamp  => SoN::IR::Stamp->new(type => 'Array'));
            }
        }

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
        if ($collect) {
            $acc_phi->set_backedge($acc_next);
            # MAP AND GREP IN SCALAR CONTEXT ARE COUNTS, not their result list.
            # Measured on 5.42.0:
            #
            #     my $n = map  { $_*2 } (1,2,3)    3   how many results
            #     my $n = grep { $_>1 } (1,2,3)    2   how many matched
            #     my @m = map  { $_*2 } (1,2,3)    the elements
            #
            # Both lower to this loop, and the scalar reading took the
            # ACCUMULATOR: `print $n` emitted Print(Coerce(Phi:Array -> Str)),
            # stringifying the result list where perl prints a count. Same class
            # as scalar reverse -- one reading given to a context-sensitive op.
            #
            # The optree says which, on the map/grepstart op itself:
            #
            #     my $n = map {...} @a    mapstart sK   want=2  scalar
            #     my @m = map {...} @a    mapstart lK   want=3  list
            #
            # Count over the accumulator, rather than a different accumulator,
            # because the loop is identical either way -- only the READING of
            # its result differs, and Count is exactly that reading.
            my $want = $collect_op ? ($collect_op->flags & 3) : 3;
            $sim->push_node(
                $want == 3 || $want == 0
                    ? $acc_phi
                    : $factory->make('Count', inputs => [$acc_phi],
                        stamp => SoN::IR::Stamp->new(type => 'Int')));
        }
        return;
    }

    # Walk a loop's condition + body ops. With $loop_node (the real walk of
    # _translate_while_loop) the condition builds Projs directly on the Loop
    # per the corpus contract and the exit Proj is returned; without it (the
    # scout walk, whose nodes are throwaway) the legacy If shape is kept --
    # the binding effects are identical either way, which is all the scout
    # measures.
    sub _walk_loop_body ($cv, $op, $sim, $factory, $opmap, $loop_visited, $outer_visited, $loop_node = undef, $break_projs = undef, $cond_consumed = 0) {
        # in_loop_body tells _restore_locals it cannot honour a `local` here:
        # the restore is per-ITERATION, and a save taken once on this walk
        # cannot express that. See its guard.
        my $ctx = { mode => 'loop', local_saves => [], in_loop_body => 1 };
        my $exit_proj;
        # A foreach's iteration `and` is consumed by its caller before the body
        # walk begins, so its body has NO loop condition left to find: the first
        # top-level `and` here is already a guard. $cond_consumed says so.
        #
        # This is deliberately NOT folded into $condition_fired. That flag means
        # "a WRITTEN header condition was consumed in THIS walk", and the
        # head-of-body `last if` hoist refuses when it is already set -- so
        # seeding it for a foreach turned `for (..) { last if C; ... }` into a
        # GAP. Two different facts, two flags.
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

            # A map/grep BODY ends by jumping back to its own mapwhile/grepwhile
            # -- that op IS the loop, reached along the back-edge, so the body is
            # complete. It cannot be a NESTED map/grep: a nested one is entered
            # through its own mapstart, which the main walker handles and which
            # consumes its while-op before the walk can reach it. Stop here, the
            # way a foreach body stops at its `unstack`, or the branch refusal
            # below reads this loop's own back-edge as unlowerable nesting.
            last if $name eq 'mapwhile' || $name eq 'grepwhile';

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

            # AN UNCONDITIONAL `next` ENDS THE BODY, and everything after it is
            # dead. It jumps to the loop's continue point -- the same `unstack`
            # this walk already stops at, one op earlier -- so the ops between
            # are unreachable and translating them would put code in the graph
            # that perl never runs. Measured on perl's t/base/while.t test 3:
            # `while ($x != 3) { $x = $x + 1; next; print "not "; }` prints no
            # "not " at all.
            #
            # The back-edge already carries the rejoin, so there is nothing to
            # record: a `next` returns to the header exactly as falling off the
            # end of the body does.
            if ($name eq 'next') {
                last;
            }

            # A bare `last`/`redo` reached directly (not via an `and(other->..)`
            # guard) is an UNCONDITIONAL loop control -- walking past one produced
            # silently wrong graphs (a dropped `last` ran the loop to completion).
            # The conditional `X if C` forms are caught at the `and` handlers
            # below; only the unconditional (or `redo`) forms reach here.
            #
            # `last` IS NOT LIKE `next` and stays refused: it LEAVES the loop, so
            # the exit Region needs its edge and the bindings live at that point
            # (which is what @break_projs collects for the guarded form). A `next`
            # rejoins the header and needs neither.
            if ($name eq 'last' || $name eq 'redo') {
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
                            && $m->operation eq 'Phi' && !_is_narrowed($m->stamp);
                        my ($a, $b) = $m->inputs->@*;
                        $m->set_stamp(SoN::IR::Stamp::join($a->stamp, $b->stamp))
                            if defined $a && defined $b
                            && _is_narrowed($a->stamp) && _is_narrowed($b->stamp);
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

            # MID-BODY GUARDED STATEMENT: an `and` whose ->other is an
            # ordinary statement (not `last`/`next`) AFTER the loop condition has
            # already fired. Perl compiles an else-less `if (C) { STMT }` and a
            # postfix `STMT if C` to the SAME `and` shape as the loop's own
            # iteration guard, so position -- not shape -- tells them apart: the
            # first such `and` is the loop condition, a later one is a guard.
            #
            # A VALUE-CONTEXT and/or (`my $x = $i && 1`) is not a guard either:
            # it PRODUCES a value, where a guarded statement is void. perl marks
            # the difference in the op flags -- the guard is vK/1 (void), the
            # value form sK/1 (scalar) -- so gate on void context. Claiming the
            # value form left its result unmodelled and crashed the StackSim with
            # a stack underflow, which is worse than the GAP it replaced: an
            # internal error is not a refusal.
            #
            # A COMPOUND loop condition (`while (A && B)`) is NOT a guard, and
            # $stmt_count is what tells them apart: the second `and` of a
            # compound condition is still in the CONDITION, before the body's
            # first statement boundary, so $stmt_count is 0 there and the guard
            # handler declines. Lowering `while ($i<3 && $j<5)` as a guard reads
            # B as a body guard and A alone as the loop test -- the body's
            # updates become conditional while the loop keeps running, which
            # SPINS FOREVER when B fails first (perl exits after 1 iteration).
            # Short-circuit in a loop condition stays a GAP.
            #
            # This is the `next if C` split with a non-empty taken arm. There,
            # the guard-taken arm is EMPTY (skip the rest); here it RUNS the
            # guarded statement and both arms rejoin at the same place:
            #
            #   b  <|> and(other->c)   <- the guard
            #   c      ... STMT ...        guard-taken arm (b->other)
            #   f  ...                     both arms converge here (b->next)
            #
            # An if/ELSE in a loop body was never affected: perl builds a
            # cond_expr for that, which _step already lowers. Only the else-less
            # form compiles to an `and`, which is why this one shape was the
            # whole of the refusal.
            if (($name eq 'and' || $name eq 'or') && $sim->stack_depth > 0
                    && ($condition_fired || $cond_consumed)
                    && $stmt_count >= 1
                    && ($op->flags & 3) == 1      # OPf_WANT_VOID
                    && $op->can('other') && ${$op->other}
                    && !_is_loop_control_or_exit($op->other)) {
                my $cond = $sim->pop_node;
                my $if_node = $factory->make_cfg('If',
                    inputs => [$sim->control, $cond]);
                # `unless C` / `STMT or ...` compiles to an `or`, which runs the
                # guarded statement when the condition is FALSE -- the arms are
                # swapped relative to `and`. Take the sense from the op rather
                # than negating the comparison: a bare-truthiness guard
                # (`STMT unless $flag`) has no comparison to negate, and the
                # Proj index carries the sense with no node to synthesize.
                my ($taken_idx, $skip_idx) = $name eq 'or' ? (1, 0) : (0, 1);
                my $taken_proj = $factory->make_cfg('Proj',
                    inputs => [$if_node], index => $taken_idx);
                my $skip_proj  = $factory->make_cfg('Proj',
                    inputs => [$if_node], index => $skip_idx);

                # Walk the guarded statement on the taken arm, stopping where it
                # rejoins the main path. Both arms converge at the guard's
                # op_next, so bound the walk there rather than letting it run on
                # into the rest of the body (which belongs to BOTH arms).
                my $taken_sim = $sim->snapshot;
                $taken_sim->set_control($taken_proj);
                _walk_branch($cv, $op->other, $taken_sim, $factory, $opmap,
                    {}, undef, 0, _op_addr($op->next));
                # The guarded statement is a void statement; drain any value it
                # left so merge() does not build a spurious stack Phi.
                $taken_sim->pop_node while $taken_sim->stack_depth > $sim->stack_depth;

                # The skip arm holds the pre-guard bindings on Proj 1. Merge it
                # with the taken arm: arm 0 = taken, arm 1 = skipped.
                my $pre = $sim->scope_bindings;
                my $skip_sim = $sim->snapshot;
                $skip_sim->set_control($skip_proj);
                # merge()'s receiver becomes Phi arm 0, which must be the arm on
                # Proj 0 -- for an `or` that is the SKIP arm, not the taken one.
                my ($lhs, $rhs) = $name eq 'or'
                    ? ($skip_sim, $taken_sim) : ($taken_sim, $skip_sim);
                $lhs->merge($rhs, $factory, $if_node);

                # Stamp each newly-built merge Phi from the join of its arms.
                # A merge Phi over a loop-carried accumulator becomes that slot's
                # back-edge, and _patch_loop_phi rejects an UNSTAMPED back-edge.
                my $merged = $lhs->scope_bindings;
                for my $targ (keys %$merged) {
                    my $m = $merged->{$targ};
                    next unless defined $m
                        && $pre->{$targ} && $m != $pre->{$targ}
                        && $m->operation eq 'Phi' && !_is_narrowed($m->stamp);
                    my ($a, $b) = $m->inputs->@*;
                    $m->set_stamp(SoN::IR::Stamp::join($a->stamp, $b->stamp))
                        if defined $a && defined $b
                        && _is_narrowed($a->stamp) && _is_narrowed($b->stamp);
                }
                $sim->set_control($lhs->control);
                $sim->set_memory($lhs->memory);
                $sim->define($_, $merged->{$_}) for keys %$merged;

                # Resume on the not-taken path: the rest of the body runs for
                # both arms, from the merged state.
                $op = $op->next;
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
    # A guard's ->other is the STATEMENT it guards. When ->other is instead a
    # control transfer -- `last`/`next`/`redo` (loop control) or a function exit
    # (`return`/`leavesub`) -- the construct is not a guarded statement and the
    # guard handler must not claim it: loop control has its own handlers above,
    # and a `return` inside a loop body is an unbuilt feature that must keep
    # GAPping rather than lower as an ordinary two-armed merge (which would drop
    # the exit edge entirely and fall through to the back-edge).
    sub _is_loop_control_or_exit ($other) {
        my $n = $other->name;
        return 1 if $n eq 'last' || $n eq 'next' || $n eq 'redo';
        return 1 if $n eq 'return' || $n eq 'leavesub' || $n eq 'leavesublv';
        # `return EXPR` is a return op wrapping a list; the exit can also appear
        # as the first op of the guarded arm rather than as ->other itself.
        my %seen;
        for (my $o = $other; $$o && !$seen{$$o}; $o = $o->next) {
            $seen{$$o} = 1;
            my $m = $o->name;
            last if $m eq 'unstack' || $m eq 'leaveloop' || $m eq 'nextstate';
            return 1 if $m eq 'return' || $m eq 'leavesub' || $m eq 'leavesublv'
                || $m eq 'last' || $m eq 'next' || $m eq 'redo';
        }
        return 0;
    }
    # The pure comparison OPTREE ops. Keyed by optree op name (unlike
    # %COMPARISON_OP, which is keyed by IR op name): two namespaces, not two
    # copies of one table. A comparison READS its operands and yields a Boolean,
    # so it is never a read-modify-write however OPf_MOD is set.
    my %COMPARISON_OPTREE_OP = map { $_ => 1 }
        qw(eq ne lt gt le ge ncmp scmp
           i_eq i_ne i_lt i_gt i_le i_ge);
    sub _is_comparison_optree_op ($n) { return $COMPARISON_OPTREE_OP{$n} ? 1 : 0 }

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

    # $join BOUNDS THE SCAN, and $stop alone does not. $stop is the OTHER ARM,
    # which the false arm never reaches -- perl's true arm ends in a `goto` to
    # the join, so walking ->next from the false arm runs THROUGH the join and
    # into the next statement. A store there was blamed on the arm:
    #
    #     print "$h{k}" eq "v" ? "y\n" : "n\n";   <- arms are constants
    #     $h{k} = "v";                             <- found here, blamed there
    #
    # _arm_has_void_call and _arm_has_die already take the join for this reason;
    # this detector and _arm_has_field_store were never given it.
    sub _arm_has_element_store ($start, $stop, $join = undef) {
        $stop = _op_addr($stop);
        my %seen;
        for (my $op = $start; $$op && $$op != $stop && !$seen{$$op}; $op = $op->next) {
            last if defined $join && $$op == $join;
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
    # Bounded at the JOIN for the same reason as _arm_has_element_store above.
    sub _arm_has_field_store ($cv, $start, $stop, $join = undef) {
        $stop = _op_addr($stop);
        my $padlist = $cv->PADLIST;   # loop-invariant; the padname table is per-CV
        return 0 unless $$padlist;
        my $padnames = $padlist->ARRAYelt(0);
        my %seen;
        for (my $op = $start; $$op && $$op != $stop && !$seen{$$op}; $op = $op->next) {
            last if defined $join && $$op == $join;
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
        if (_is_narrowed($true_val->stamp) && _is_narrowed($false_val->stamp)) {
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
    # $exits, when given, is the FUNCTION-WIDE exit accumulator. An arm that
    # returns records its control edge there so _build_single_exit merges it
    # with every other exit; without it the arm's exit is detected and dropped,
    # which is why this used to refuse. The statement-modifier path has always
    # passed it -- this is the same threading, one construct over.
    sub _handle_cond_expr ($cv, $op, $sim, $factory, $opmap, $visited, $exits = undef) {
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
            # RECORD INTO THE FUNCTION-WIDE LIST when the caller gave us one:
            # an arm that returns is a control edge to the function exit, and
            # _build_single_exit merges it with the others into one Return.
            # Falling back to a local accumulator keeps the old refusal for a
            # caller that cannot thread exits (the loop-body walk), where
            # dropping one would be silent.
            my @arm_exits;
            my $exit_sink = $exits // \@arm_exits;
            my ($end, $sig) = _walk_branch($cv, $start, $arm_sim, $factory,
                $opmap, $visited, $exit_sink, 1, $join_addr);
            die "GAP: function exit inside an if/else arm not yet lowered\n"
                if ($sig // '') eq 'exited' && !defined $exits;
            # An arm stopping anywhere OTHER than the join hit an op the
            # walker cannot translate -- and it marked that op visited, so
            # the main walk would terminate there too, silently dropping
            # everything after the if/else. Refuse loudly.
            # AN EXITING ARM DOES NOT REACH THE JOIN, and that is correct
            # rather than a failure: it left the function. Its control edge is
            # already recorded in the exit list, so there is nothing to merge
            # at the join and nothing after it in this arm to drop.
            if (defined $join_addr
                && ($sig // '') ne 'exited'
                && !(defined $end && ref $end && $$end == $join_addr)) {
                my $where = (defined $end && ref $end && $$end)
                    ? $end->name : 'end-of-chain';
                die "GAP: untranslatable op inside an if/else arm"
                  . " (arm stopped at `$where`, not the join) not yet lowered\n";
            }
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
        my $elem_branch = _arm_has_element_store($op->other, $op->next, $join_addr)   # true arm
                       || _arm_has_element_store($op->next, $op->other, $join_addr);  # false arm
        my $mem_branch  = $elem_branch
                       || _arm_has_field_store($cv, $op->other, $op->next, $join_addr)
                       || _arm_has_field_store($cv, $op->next, $op->other, $join_addr)
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
        # VISITED RIDES ON THE CTX so a handler that walks a nested structure --
        # a foreach body, say -- marks the same op set the caller does. Without
        # it the arm and the main walk keep separate views and an op walked in
        # one is re-walked by the other.
        my $ctx = { mode => 'branch', visited => $visited,
                    local_saves => [] };
        # The arm's ENTRY op, kept because $op is mutated by the walk below. A
        # back-edge test needs it: "did this unstack jump to something on the
        # path we have already walked" is the question, and the path starts
        # here.
        my $arm_start = $op;
        # ...and the stack depth on entry, so a handler that re-walks a nested
        # construct can drop back to it rather than guess.
        my $arm_base_depth = $sim->stack_depth;
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

            # VALUE-CONTEXT `&&` / `||` INSIDE AN ARM. The main walk lowers
            # these to a single operand-returning And/Or node (the backend
            # expands the short-circuit br+phi at lowering, the same split
            # DefinedOr uses for `//`). _walk_branch had no handler at all, so
            # an arm containing one stopped at the `or`, never reached the join,
            # and the caller's "untranslatable op" backstop refused the whole
            # if/else. The construct was already buildable; only this walker
            # could not build it.
            #
            #     c  <|> or(other->d) lK/1     inside the arm
            #     d      <$> const[IV 5]       the RHS value
            #     e  <@> print vK              both sides converge here
            #
            # THE GUARD MUST MATCH THE MAIN WALK'S, not just "is there a
            # value on the stack". _walk_branch is reached from more than an
            # if/else arm -- a chained `open(...) || open(...) || (die ...)`
            # walks its left `||` through here too. Claiming a VOID or
            # die/store/void-call arm broke perl's own t/base/term.t, which
            # spells exactly that: the arm produces no value, so this handler
            # GAPped a line the main walk had always lowered. Those forms need
            # real control flow and belong to the handlers that build it.
            #
            # ONLY THE VALUE FORM. The main walk's handler also covers a
            # statement-modifier exit (`return 1 if $x`), an element-store arm
            # and a `die` arm -- each needing real control flow. Those keep
            # GAPping here: an arm whose RHS exits or stores is not a value, and
            # a wrong answer is worse than a refusal. Detected by walking the
            # RHS on a snapshot and requiring it to produce exactly one value
            # and converge at this op's op_next.
            if ($opmap->is_branch($name) && ($name eq 'and' || $name eq 'or')
                    && $sim->stack_depth > 0
                    && ($op->flags & 3) != 1            # not OPf_WANT_VOID
                    && !_arm_has_die($op->other, ${ $op->next })
                    && !_arm_has_void_call($op->other, ${ $op->next })
                    && !_arm_has_element_store($op->other, ${ $op->next })) {
                my $lhs      = $sim->pop_node;
                my $base     = $sim->stack_depth;
                my $stop     = ${ $op->next };
                my $rhs_sim  = $sim->snapshot;
                my @rhs_exits;
                my ($rhs_end, $rhs_sig) =
                    _walk_branch($cv, $op->other, $rhs_sim, $factory, $opmap,
                        $visited, \@rhs_exits, 1, $stop);
                # An exiting or non-converging RHS is the control-flow form.
                die "GAP: short-circuit with a non-value arm inside an if/else"
                  . " arm not yet lowered\n"
                    if ($rhs_sig // '') eq 'exited'
                    || @rhs_exits
                    || !(defined $rhs_end && ref $rhs_end && $$rhs_end == $stop);
                die "GAP: short-circuit whose arm is not a single value inside"
                  . " an if/else arm not yet lowered\n"
                    unless $rhs_sim->stack_depth == $base + 1;
                my $rhs = $rhs_sim->pop_node;
                $sim->push_node($factory->make(
                    $name eq 'and' ? 'And' : 'Or', inputs => [$lhs, $rhs]));
                $op = $rhs_end;
                next;
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
                    $visited, $exits);
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
                # A LOOP, NOT A MODIFIER, and still refused -- but now for a
                # measured reason rather than "unhandled op".
                #
                # Routing it to _translate_while_loop from HERE builds a Loop
                # node whose condition is disconnected from its own induction
                # variable: measured on
                # `if (C) { 1 while $n++ < 3 }`, the graph came out with
                # NumLt(Constant, Constant) -- $n's increment never reaches the
                # test, so the loop's trip count is whatever the constants say.
                # A Loop with no loop-carried Phi is a silent miscompile, which
                # is worse than the refusal it replaced.
                #
                # The cause is that _translate_while_loop expects the CONDITION
                # HEAD (enter->next) and the pre-loop bindings the main walk has
                # established by then; entered at the and/or from inside an arm
                # it has neither, so its Phi-based re-walk finds nothing to
                # carry. Detecting the shape is done (_and_is_loop_back_edge);
                # giving it the right entry state is the remaining work.
                if (_and_is_loop_back_edge($op, $arm_start)) {
                    # THE CONDITION HEAD IS WHAT THE TRANSLATOR WANTS, and it
                    # is `enter->next` -- the op the body's unstack jumps back
                    # to. Entering at the and/or instead gave it a stack with
                    # the condition's own operands already on it and no way to
                    # know where the loop begins, which is why the Phi came out
                    # unconnected.
                    my $cond_head = _loop_cond_head($op);
                    die "GAP: a postfix-while loop inside an if/else arm whose"
                      . " condition head is not reachable is not yet lowered\n"
                        unless $cond_head;

                    # Drop the condition operands this walk has already pushed:
                    # _translate_while_loop re-walks the condition itself, from
                    # a clean stack, exactly as the main walk hands it one.
                    $sim->pop_node while $sim->stack_depth > $arm_base_depth;

                    _translate_while_loop($cv, $cond_head, $sim, $factory,
                        $opmap, $visited);

                    # Continue after the loop, at the enclosing `leave`.
                    my %skip;
                    my $after = $op;
                    while ($$after && $after->name ne 'leave'
                               && !$skip{$$after}++) {
                        $after = $after->next;
                    }
                    $op = $$after ? $after->next : $after;
                    next;
                }

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
                # RECORD INTO THE FUNCTION-WIDE LIST, exactly as the if/else
                # arm does (2db8ba5). `return X if C` nested inside an arm is
                # an exit two constructs deep; its control edge belongs in the
                # shared accumulator so _build_single_exit merges it with every
                # other exit. Handing it a local list detected the exit and
                # dropped it, which left refusing as the only honest option.
                my @mod_exits;
                my $mod_sink = $exits // \@mod_exits;
                my ($mod_end, $mod_sig) = _walk_branch($cv, $op->other,
                    $mod_sim, $factory, $opmap, $visited, $mod_sink,
                    1, $mod_stop);
                die "GAP: function exit inside a statement modifier in an"
                  . " if/else arm not yet lowered\n"
                    if ($mod_sig // '') eq 'exited' && !defined $exits;
                # A back-edge (the body re-enters an already-visited op) is a
                # statement-modifier LOOP, not a rebind -- refuse loudly.
                #
                # AN EXITING MODIFIER DOES NOT REACH $mod_stop, and that is
                # correct rather than a failure: it left the function, so there
                # is no convergence to check and nothing after it to drop.
                die "GAP: statement-modifier loop or unhandled op inside an"
                  . " if/else arm not yet lowered\n"
                    unless ( ($mod_sig // '') eq 'exited' )
                        || ( defined $mod_end && ref $mod_end
                             && $$mod_end == $mod_stop );
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
    # *main::_, so it is modeled as a EntryDef (a real array source), never a
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
    # _sort_fields($op) -- what a FOLDED sort compares, and in which direction.
    #
    # perl folds the standard comparators into flags on the op, which is why
    # they carry no block. Without those flags on the wire three programs with
    # three different answers arrive byte-identical:
    #
    #     sort { $a <=> $b } (3,1,2)   perl 1
    #     sort { $b <=> $a } (3,1,2)   perl 3
    #     sort (3,1,2)                 perl 1
    #
    # A consumer picking one behaviour silently miscompiles the other two -- a
    # silent AMBIGUITY rather than a silent drop. Reported by chalk.
    #
    # BARE SORT IS STRING COMPARISON, which is the row that bites ordinary
    # code: `sort (10, 9, 100)` is `10 100 9`, not `9 10 100`. A consumer
    # assuming numeric because the common case looks numeric is wrong on plain
    # perl. `sort { $a cmp $b }` folds to the same thing, correctly.
    #
    # Measured (OPpSORT_NUMERIC 0x1, OPpSORT_DESCEND 0x10):
    #
    #     sort { $a <=> $b }   private=0x01   numeric ascending
    #     sort { $b <=> $a }   private=0x11   numeric descending
    #     sort { $a cmp $b }   private=0x00   string  ascending
    #     sort                 private=0x00   string  ascending
    #
    # Read off the op, so T1 states what the program says rather than inferring.
    sub _sort_fields ($op) {
        my $priv = $op->private;
        return (
            sort_cmp   => ( $priv & 1 )    ? 'numeric'    : 'string',
            sort_order => ( $priv & 0x10 ) ? 'descending' : 'ascending',
        );
    }

    sub _stash_key ($node) {
        return $node->stash_name . '::' . $node->sigil . $node->var_name;
    }

    # `@_` IS AN ARRAY, and that is true structurally -- for every sub, with no
    # inference. It has storage: you can shift it, index it, take scalar @_.
    #
    # Not `List`: that is the flattening notion, what a comma expression yields
    # in list context, and the consumer refuses it as "signature vocabulary,
    # not a value type". Not `ArrayRef` either -- that is a REFERENCE to an
    # array, a different thing. The container's own type is Array.
    #
    # This defaulted to `Unknown`, which claimed inference had failed when in
    # fact nothing had ever asked. Measured on the consumer side, it was the
    # largest single class of untyped value node reaching the end of the
    # analysis pipeline.
    #
    # It types the CONTAINER only. Readers -- `shift`, `$_[0]` -- produce their
    # own nodes typed from the callsite, and are unaffected: an Int argument
    # still shifts out as Int. What stays out of reach is `my @a = @_`, which
    # binds the whole list and so needs the ELEMENT type; that is the
    # Array[Scalar] wall, and it remains a GAP.
    sub _args_source ($factory) {
        return $factory->make('ArgsSource',
            stamp => SoN::IR::Stamp->new(type => 'Array'));
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
