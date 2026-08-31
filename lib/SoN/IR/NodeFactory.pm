# ABOUTME: Factory for Chalk IR nodes with hash consing for data nodes.
# ABOUTME: make() deduplicates data nodes by content hash; make_cfg() creates unique CFG nodes.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use SoN::IR::Stamp;
use B::SoN::TypeLibrary;
use SoN::IR::Node::Constant;
use SoN::IR::Node::Phi;
use SoN::IR::Node::Add;
use SoN::IR::Node::Subtract;
use SoN::IR::Node::Multiply;
use SoN::IR::Node::Divide;
use SoN::IR::Node::Modulo;
use SoN::IR::Node::Power;
use SoN::IR::Node::Concat;
use SoN::IR::Node::NumEq;
use SoN::IR::Node::NumNe;
use SoN::IR::Node::NumLt;
use SoN::IR::Node::NumGt;
use SoN::IR::Node::NumLe;
use SoN::IR::Node::NumGe;
use SoN::IR::Node::NumCmp;
use SoN::IR::Node::StrEq;
use SoN::IR::Node::StrNe;
use SoN::IR::Node::StrLt;
use SoN::IR::Node::StrGt;
use SoN::IR::Node::StrLe;
use SoN::IR::Node::StrGe;
use SoN::IR::Node::StrCmp;
use SoN::IR::Node::And;
use SoN::IR::Node::Or;
use SoN::IR::Node::BitAnd;
use SoN::IR::Node::BitOr;
use SoN::IR::Node::BitXor;
use SoN::IR::Node::LeftShift;
use SoN::IR::Node::RightShift;
use SoN::IR::Node::Assign;
use SoN::IR::Node::Repeat;
use SoN::IR::Node::Match;
use SoN::IR::Node::NotMatch;
use SoN::IR::Node::DefinedOr;
use SoN::IR::Node::Xor;
use SoN::IR::Node::Range;
use SoN::IR::Node::Yada;
use SoN::IR::Node::IsaOp;
use SoN::IR::Node::Not;
use SoN::IR::Node::Negate;
use SoN::IR::Node::Complement;
use SoN::IR::Node::Defined;
use SoN::IR::Node::UnaryPlus;
use SoN::IR::Node::Ref;
use SoN::IR::Node::RefType;
use SoN::IR::Node::Length;
use SoN::IR::Node::Count;
use SoN::IR::Node::Slice;
use SoN::IR::Node::PadAccess;
use SoN::IR::Node::FieldAccess;
use SoN::IR::Node::EntryDef;
use SoN::IR::Node::ArgsSource;
use SoN::IR::Node::Parameter;
use SoN::IR::Node::Subscript;
use SoN::IR::Node::Call;
use SoN::IR::Node::HashRef;
use SoN::IR::Node::ArrayRef;
use SoN::IR::Node::Interpolate;
use SoN::IR::Node::AnonSub;
use SoN::IR::Node::RegexMatch;
use SoN::IR::Node::RegexSubst;
use SoN::IR::Node::RegexCapture;
use SoN::IR::Node::Print;
use SoN::IR::Node::EnvRead;
use SoN::IR::Node::TryCatch;
use SoN::IR::Node::PostfixDeref;
use SoN::IR::Node::CompoundAssign;
use SoN::IR::Node::BacktickExpr;
use SoN::IR::Node::VarDecl;
use SoN::IR::Node::ListAssign;
use SoN::IR::Node::TernaryExpr;
use SoN::IR::Node::StructRef;
use SoN::IR::Node::StructFieldAccess;
use SoN::IR::Node::Start;
use SoN::IR::Node::MemStart;
use SoN::IR::Node::Return;
use SoN::IR::Node::Unwind;
use SoN::IR::Node::If;
use SoN::IR::Node::Proj;
use SoN::IR::Node::Region;
use SoN::IR::Node::Loop;
use SoN::IR::Node::ExpressionList;
use SoN::IR::Node::Coerce;

my %DATA_CLASSES = map { $_ => "SoN::IR::Node::$_" } qw(
    Constant Phi
    Add Subtract Multiply Divide Modulo Power Concat
    NumEq NumNe NumLt NumGt NumLe NumGe NumCmp
    StrEq StrNe StrLt StrGt StrLe StrGe StrCmp
    And Or BitAnd BitOr BitXor LeftShift RightShift
    Assign Repeat Match NotMatch DefinedOr Xor Range Yada IsaOp
    Not Negate Complement Defined UnaryPlus Ref RefType Length Count
    PadAccess FieldAccess EntryDef ArgsSource Parameter Subscript Slice
    Call HashRef ArrayRef
    Interpolate AnonSub
    RegexMatch RegexSubst RegexCapture Print EnvRead TryCatch
    PostfixDeref CompoundAssign BacktickExpr VarDecl ListAssign
    TernaryExpr StructRef StructFieldAccess
    ExpressionList
    Start MemStart Return Unwind
    Coerce
);

# CFG ops that are NEVER hash-consed via make_cfg (each call allocates fresh).
# Start/Return/Unwind appear in %DATA_CLASSES too — they are hash-consed when
# constructed via make() (legacy Bootstrap API shape) but allocated fresh
# when constructed via make_cfg() (every call gets a unique cfg_counter id).
# Callers picking between the two pick by semantic intent: make() for shared
# entry/exit/sentinel positions, make_cfg() for per-statement control nodes.
my %CFG_CLASSES = map { $_ => "SoN::IR::Node::$_" } qw(
    Start Return Unwind If Proj Region Loop
);

# Ops that have CFG semantics (per-position identity, never hash-consed
# by content) but are constructed via make() rather than make_cfg().
# Mirrors Bootstrap::IR::NodeFactory's %CFG_OPS. Start/Return/Unwind are
# NOT in this set — they go through the hash-cons path in make() to
# match Bootstrap's permissive-make-of-Start behavior.
my %ROUTED_CFG = map { $_ => 1 } qw(If Proj Region Phi Loop);

# Per-op input-keyword mapping. Mirrors Bootstrap's %INPUT_SPECS:
# Actions.pm passes named params (control => ..., condition => ...,
# value => ...) and make() translates those into inputs => [...] in the
# order listed. Applies to both ROUTED_CFG ops and hash-consed CFG-like
# ops (Return/Unwind), so callers can use either inputs => [...] or
# named-keyword shape — typed factory handles both.
my %INPUT_SPECS = (
    If     => ['control', 'condition'],
    Proj   => ['source'],
    Region => ['controls'],
    Loop   => ['entry_ctrl', 'backedge_ctrl'],
    Return => ['value'],   # though Actions uses inputs => [$ctrl, $val]
    Unwind => ['value'],
    # Phi has its own handler at make() top
);

class SoN::IR::NodeFactory {
    # Statement-effect ops: ops whose occurrences are distinct side effects
    # (a store, a call, a substitution, a guarded block — and a MATCH: it
    # executes against its subject and writes capture state, so two
    # textually-identical matches at different program points are distinct
    # effects with their own capture records; likewise qx``). control_in is
    # excluded from the content hash, so hash-consing these would collapse
    # two textually-identical effects into one node and silently drop or
    # stale-serve the second (whole-branch review C3; 019eb6ff item 1).
    # This table is a SHARED contract: make() gives these ops per-call
    # identity, the Block control-chain fixup in Actions.pm threads exactly
    # this set via set_control_in, and the LLVM backend's chain/branch
    # collectors read it. Keep it the single source.
    our %STATEMENT_EFFECT_OPS = map { $_ => 1 } qw(
        Assign CompoundAssign RegexSubst TryCatch Call
        RegexMatch Match NotMatch BacktickExpr Print
    );

    # Allocation ops: aggregate literal constructors. Each occurrence
    # ALLOCATES (the Call(new) precedent) — `[1,2]` and `[1,2]` are two
    # distinct arrays, so hash-consing them to one node made one malloc
    # that the two "distinct" refs silently aliased (019eb6ff item 4).
    # Per-call identity like the statement effects, but NOT in
    # %STATEMENT_EFFECT_OPS: allocations are value-producing and are not
    # control-threaded by the Block fixup.
    our %ALLOC_OPS = map { $_ => 1 } qw(ArrayRef HashRef);

    # Aggregate LITERAL CONSTRUCTORS. Not operators: `[1,2]` yields a ref to
    # the array it just built, and no TypeLibrary signature describes that —
    # result_for returns undef for both. Their type comes from the syntax that
    # built the node, not from a signature, so it is stated here.
    #
    # The OPERATORS that used to sit in this table (RefType, Defined,
    # RegexMatch, NotMatch, Not) are gone from it. What an operator yields is a
    # fact about the OPERATOR, and those live in B::SoN::TypeLibrary — asked
    # for below rather than copied here, so the two cannot drift. Do NOT add an
    # op here to silence an untyped-node failure: if TypeLibrary cannot say,
    # that is an open question, and a literal here makes it a wrong answer.
    # The LITERAL CONSTRUCTORS that used to sit here (ArrayRef, HashRef) are
    # gone from it too, but for the opposite reason: TypeLibrary cannot say
    # what they yield, because there is no operator and no operand to ask
    # about. That makes their type a fact about the CLASS, and each now
    # declares it via default_stamp_type (see SoN::IR::Node::ArrayRef).
    #
    # Nothing is left to tabulate. The table is retired rather than kept empty:
    # an empty one is an invitation to refill it, which is what this comment
    # exists to refuse.

    field %cache;
    field $cfg_counter = 0;

    # Every SoN::IR::Value carries a stamp — undef is not a state a value
    # node may be in (see SoN::IR::Value). Rather than require all ~80
    # construction sites to remember, the guarantee is established once here,
    # at the single chokepoint every data node passes through.
    #
    # `Unknown` is the fallback because it is an ANSWER, not an absence: a
    # real lattice member with defined join/meet, so downstream inference can
    # compute with it. A caller that KNOWS the type still passes it and wins —
    # this only fills the gap where nothing was said.
    # A stamp is a SoN::IR::Stamp OBJECT, not a type name -- the serializer
    # reads $node->stamp->type and Stamp::join operates on the objects. A
    # plain string here would satisfy `defined` and then die at serialization.
    method _default_stamp($op_name, %args) {
        return %args if defined $args{stamp};
        my $class = $DATA_CLASSES{$op_name} // $CFG_CLASSES{$op_name};
        return %args unless $class && $class->isa('SoN::IR::Value');
        # ASK, DO NOT COPY. result_for with NO OPERANDS answers for exactly the
        # ops whose result is fixed by the operation itself (`!$x` is Boolean
        # however wide $x is, `ref($x)` is Str). Those five used to be copied
        # into a table here; the copy is gone, because what an operator yields
        # is a fact about the OPERATOR and B::SoN::TypeLibrary already states
        # it. A join op (Add) reached with no operands returns undef, as does
        # an op the table does not describe.
        #
        # A node kind that knows its OWN type is not stamped here: it declares
        # default_stamp_type, and SoN::IR::Value's ADJUST consults that.
        # Leaving the stamp unset is what lets the class answer -- anything set
        # here arrives as an EXPLICIT stamp and would outrank the class's own
        # fact, stamping `[]` as Unknown. Test the VALUE, not just `can`: every
        # Value inherits the base sub, which returns undef for the vast
        # majority that have no such fact.
        return %args if $class->default_stamp_type;

        # Unknown otherwise. It is an ANSWER, not an absence: a real lattice
        # member with defined join/meet, so downstream inference can compute
        # with it, and it is what a Subscript or a Call honestly is at
        # construction time.
        $args{stamp} = SoN::IR::Stamp->new(
            type => B::SoN::TypeLibrary::result_for($op_name) // 'Unknown'
        );
        return %args;
    }

    method _register_consumers($node, %args) {
        my $inputs = $args{inputs} // [];
        for my $input ($inputs->@*) {
            next unless defined $input;
            if ( ref($input) eq 'ARRAY' ) {
                for my $elem ($input->@*) {
                    next unless defined $elem;
                    $elem->add_consumer($node);
                }
            }
            else {
                $input->add_consumer($node);
            }
        }
    }

    # Permissive node construction. Accepts both data ops (hash-consed by
    # content) and CFG-routed ops (If/Proj/Region/Phi/Loop — allocated
    # fresh per call with a counter-suffixed id, mirroring Bootstrap's
    # %CFG_OPS shape). This matches Bootstrap::IR::NodeFactory::make()'s
    # behavior so Actions.pm can route every call through the typed
    # factory without distinguishing between make() and make_cfg() shapes.
    method make($op_name, %args) {
        %args = $self->_default_stamp($op_name, %args);

        # Phi has historical CFG-style identity in Bootstrap (never
        # deduplicated) but SoN::IR::Node::Phi takes `region` as a
        # named :param and the values arrayref as `inputs`. Bootstrap's
        # legacy call shape passes `region => ..., values => ...` — keep
        # that shape working here.
        if ($op_name eq 'Phi') {
            my $class = $DATA_CLASSES{Phi};
            my $region = delete $args{region};
            my $values = delete $args{values};
            $cfg_counter++;
            my $id = "Phi#${cfg_counter}";
            my $node = $class->new(
                id     => $id,
                region => $region,
                inputs => (defined $values ? $values : []),
                %args,
            );
            # Register consumers from the values arrayref AND the region.
            # The region is a use-def input even though it's tracked as a
            # named field rather than via inputs() — Bootstrap's
            # %INPUT_SPECS treats it the same way.
            if (defined $region) {
                $region->add_consumer($node);
            }
            if (defined $values) {
                for my $el ($values->@*) {
                    next unless defined $el;
                    $el->add_consumer($node);
                }
            }
            # The JSON loader (Serialize::JSON::_deserialize_graph) builds a
            # deserialized Phi's inputs via `inputs => [...]`, not `values`,
            # so $values is undef on that path and the loop above never
            # runs. Register consumers from the plain `inputs` key too, via
            # the same generic helper make_cfg() uses, so a round-tripped
            # Phi's init input gets back-registered. Mutually exclusive with
            # the $values branch above (a caller passes one key or the
            # other, never both) and safe against the loader's deferred
            # loop-Phi backedge patch: the forward-referenced backedge is
            # excluded from `inputs` at construction time and wired later
            # via Phi::set_backedge, which does its own add_consumer.
            elsif (defined $args{inputs}) {
                $self->_register_consumers($node, inputs => $args{inputs});
            }
            $cache{$id} = $node;
            return $node;
        }

        # Routed-CFG ops: allocated fresh, never hash-consed. They have
        # CFG semantics (distinct positions in control flow) but used to
        # be constructed via Bootstrap::make() rather than make_cfg.
        # Treat them like make_cfg() for identity, like make() for caller
        # convenience.
        # Translate Bootstrap's named-input keywords into inputs => [...]
        # in declared order. Applies to any op with an INPUT_SPECS entry;
        # callers using inputs => [...] directly pass through unchanged.
        # Mirrors Bootstrap::IR::NodeFactory::make's behavior.
        if (exists $INPUT_SPECS{$op_name} && !exists $args{inputs}) {
            my @inputs;
            for my $name ($INPUT_SPECS{$op_name}->@*) {
                push @inputs, delete $args{$name};
            }
            $args{inputs} = \@inputs;
        }

        if (exists $ROUTED_CFG{$op_name}) {
            my $class = $CFG_CLASSES{$op_name}
                or die "Unknown CFG node operation: $op_name";
            $cfg_counter++;
            my $id = "${op_name}#${cfg_counter}";
            my $node = $class->new( id => $id, %args );
            $self->_register_consumers($node, %args);
            $cache{$id} = $node;
            return $node;
        }

        # VarDecl is a statement-position side-effect node with per-position
        # (counter) identity, like Return/Unwind: two textually-identical
        # declarations in different control positions are distinct nodes,
        # each carrying its own control_in decoration. Allocate a fresh id
        # per call; never hash-cons by content.
        if ($op_name eq 'VarDecl') {
            my $class = $DATA_CLASSES{VarDecl};
            $cfg_counter++;
            my $id = "VarDecl#${cfg_counter}";
            my $node = $class->new( id => $id, %args );
            $self->_register_consumers($node, %args);
            $cache{$id} = $node;
            return $node;
        }

        # ListAssign has the same per-position identity semantics as VarDecl:
        # each list declaration occupies a distinct control position.
        if ($op_name eq 'ListAssign') {
            my $class = $DATA_CLASSES{ListAssign};
            $cfg_counter++;
            my $id = "ListAssign#${cfg_counter}";
            my $node = $class->new( id => $id, %args );
            $self->_register_consumers($node, %args);
            $cache{$id} = $node;
            return $node;
        }

        # Statement-effect ops (see %STATEMENT_EFFECT_OPS above) get per-call
        # identity: every Assign (scalar rebind, element store, field store),
        # CompoundAssign, RegexSubst, TryCatch, and Call — any dispatch kind —
        # is a distinct side effect at its own control position. This subsumes
        # the earlier narrower carve-outs (Assign-over-lvalue, Call-method) and
        # the deleted ArrayWrite/HashWrite/FieldWrite per-call semantics.
        if (exists $STATEMENT_EFFECT_OPS{$op_name} || exists $ALLOC_OPS{$op_name}) {
            my $class = $DATA_CLASSES{$op_name}
                or die "Unknown node operation: $op_name";
            $cfg_counter++;
            my $id = "${op_name}#${cfg_counter}";
            my $node = $class->new( id => $id, %args );
            $self->_register_consumers($node, %args);
            $cache{$id} = $node;
            return $node;
        }

        my $class = $DATA_CLASSES{$op_name}
            or die "Unknown data node operation: $op_name";

        # Create a temp node to compute content_hash
        my $tmp = $class->new( id => '_tmp', %args );
        my $hash = $tmp->content_hash();

        # Return cached node if one exists with this hash
        return $cache{$hash} if exists $cache{$hash};

        # On miss: re-create with content hash as id
        my $node = $class->new( id => $hash, %args );
        $self->_register_consumers($node, %args);
        $cache{$hash} = $node;
        return $node;
    }

    # Construct a data node WITHOUT hash-consing, even when its op would
    # normally dedupe by content_hash. B::SoN's FromOptree scout walk (a
    # throwaway pre-pass detecting loop-carried slot mutation) builds
    # placeholder Constants that must stay independently identifiable by
    # object identity even when their content (e.g. value => 'scout') is
    # identical across placeholders — hash-consing them to one node would
    # silently break the mutation check ($after != $ph). Mirrors
    # SoN::IR::NodeFactory::make_unique.
    method make_unique($op_name, %args) {
        %args = $self->_default_stamp($op_name, %args);

        my $class = $DATA_CLASSES{$op_name}
            or die "Unknown data node operation: $op_name";
        $cfg_counter++;
        my $id = "${op_name}#unique${cfg_counter}";
        my $node = $class->new( id => $id, %args );
        $self->_register_consumers($node, %args);
        $cache{$id} = $node;
        return $node;
    }

    method make_cfg($op_name, %args) {
        my $class = $CFG_CLASSES{$op_name}
            or die "Unknown CFG node operation: $op_name";

        $cfg_counter++;
        my $id = "${op_name}#${cfg_counter}";
        my $node = $class->new( id => $id, %args );
        $self->_register_consumers($node, %args);
        return $node;
    }

    # Cache inspection / mutation API used by passes that walk the
    # full set of constructed data nodes (e.g. DCE). Mirrors the
    # Bootstrap factory's interface so passes can operate on either.
    # Cache keys are content_hash strings (same as each node's id()).
    method all_node_ids() {
        return [keys %cache];
    }

    method get_node($id) {
        return $cache{$id};
    }

    method remove_node($id) {
        my $node = delete $cache{$id};
        return defined $node ? 1 : 0;
    }

    method node_count() {
        return scalar keys %cache;
    }
}

# is_statement_node($op) -> bool
# True for ops the backend collectors treat as statement-position body
# members: VarDecl plus every statement-effect op (the shared
# %STATEMENT_EFFECT_OPS table). NOT control flow (If/Loop) — callers that
# also collect control add those explicitly. One predicate so adding an op
# to the table is a single-site change, not a sweep across the collectors.
sub SoN::IR::NodeFactory::is_statement_node {
    my ($op) = @_;
    return 0 unless defined $op;
    return 1 if $op eq 'VarDecl';
    return exists $SoN::IR::NodeFactory::STATEMENT_EFFECT_OPS{$op} ? 1 : 0;
}
