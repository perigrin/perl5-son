# ABOUTME: Base class for all IR nodes in the Chalk Sea of Nodes representation.
# ABOUTME: Provides id, use-def chains, content_hash, stamp, and compat_class fields.
use 5.42.0;
use utf8;
use experimental 'class';

class SoN::IR::Node {

    # Stable content-based ID for the node
    field $id :param :reader;

    # Producer nodes - nodes that produce values consumed by this node
    field $inputs :param :reader = [];

    # Consumer nodes - nodes that consume values produced by this node
    # This is mutable to allow building the graph
    field $consumers :reader = [];

    # Optional stamp for identifying parse-origin or generation context
    field $stamp        :param :reader = undef;

    # Optional compat_class overrides the result of class() for back-compat
    field $compat_class :param :reader = undef;

    # Effect-chain predecessor when this node appears as a statement-position
    # side effect (bare Call, bare Assign, etc.). Set by the Block control-
    # chain fixup pass via set_control_in(); undef for nodes in pure-data
    # position. Not part of content_hash: side-effect vs pure-data uses of
    # the same content (e.g. `foo()` as statement vs as expression) should
    # still hash-cons to the same node; control_in is a per-use decoration.
    field $control_in :reader = undef;

    # THE MEMORY VERSION THIS NODE READS OR FOLLOWS (wire v2's `mem_in`): a
    # MemStart, a memory Phi, or a node with mem_out. Given to make() as
    # `mem => $sim->memory` by a node that READS memory where it is built --
    # then it is part of the content hash, so reads at two versions are two
    # nodes, and wire v1 carried it as the trailing input (mem_operand). Set
    # by _pin otherwise, for what follows the chain (an Assign, a sub call, a
    # Return): not identity, as control_in is not.
    field $mem_in :param(mem) :reader = undef;
    field $mem_operand :reader = 0;
    # THIS NODE IS A MEMORY VERSION (wire v2's `mem_out`): what _place did.
    field $mem_out :reader = 0;
    ADJUST { $mem_operand = 1 if defined $mem_in }

    method set_mem_in($m) {
        die "set_mem_in: a memory operand is identity, not a decoration\n" if $mem_operand;
        $mem_in = $m;
        return;
    }
    method set_mem_out($b = 1) { $mem_out = $b ? 1 : 0; return }

    # A NODE ONLY WIRE v2 HAS A PLACE FOR (the memory Phi a Return names where
    # a sub's exits merge): wire v1 leaves it out.
    field $v2_only :reader = 0;
    method set_v2_only() { $v2_only = 1; return }

    # THE INPUTS AS WIRE v1 HAD THEM: the memory operand last. What the
    # walker's own questions were written against (a Subscript of two inputs
    # is a place, the last input of a pinned read is the memory before it);
    # a copy, so it cannot be written through.
    # shortcut: the walker still asks its questions in v1's shape; read
    # mem_in where a question is about memory, then retire this (wire v2
    # plan, stage 6 deletes v1).
    method v1_inputs() { [ $inputs->@*, ( $mem_operand ? $mem_in : () ) ] }

    # Does a node of this kind read or write memory when it stands on the
    # chain (wire v2 plan, 3.3)? _pin gives such a node the memory it follows.
    # Print, the control nodes, a pinned value (a loop test, a division that
    # may fault, an allocation) touch none.
    my %TOUCHES_MEMORY = map { $_ => 1 } qw(
        Assign EntryWrite CellWrite Delete ElemRestore MakeCell LocalAlias Call
        RegexSubst Transliterate Chomp
        Subscript Exists Count Slice RefType PostfixDeref Ref CellRead FieldAccess EntryDef PadAccess
        Return Unwind
    );
    method touches_memory() { $TOUCHES_MEMORY{ $self->operation } ? 1 : 0 }

    # Per-node scheduler interpretation, populated lazily by the scheduler
    # via set_schedule_data(). Holds a ScheduleMeta from chalk's scheduler
    # subclass instance whose dialect (EagerPinning, GCM, ...) matches the
    # scheduler that produced the current Schedule. Excluded from
    # content_hash for the same reason as control_in: it is a per-use
    # decoration, not a structural property of the node's content.
    field $schedule_data :reader = undef;

    # Machine-level representation of the value produced by this node.
    # Realized lattice (see typed-ir-representation.md): 'Bool' (i1),
    # 'Int' (i64), 'Num' (double/f64), 'Str' ({ptr,len,encoding}),
    # 'Undef'/'Slot' ({defined,payload}), 'Array' ({len,cap,Slot*}),
    # 'Hash' (linear-scan table), 'ArrayRef'/'HashRef' (i8* to the boxed
    # aggregate), 'Object' (i8* to {vtable*, Slot...}); plus the older
    # 'Ptr'/'Struct'/'Scalar' (boxed Perl SV*, conservative fallback).
    # Set post-construction by the IR builder or a lowering pass via
    # set_representation(); undef = not yet assigned.
    # Excluded from content_hash: representation is a per-use lowering
    # decision, not a structural property of what value the node IS. Two
    # nodes with identical content (same literal, same operation, same
    # inputs) must still hash-cons to one node regardless of what
    # representation the builder later assigns. Coerce nodes (§2 of
    # typed-ir-representation.md) bridge between representations on edges.
    field $representation :reader = undef;

    # WHEN EACH CONSUMER EDGE WAS MADE, one count over every node: wire v1's
    # writer orders the nodes by a walk over consumer lists, and to keep v1
    # as it was where wire v2 moved an edge (a pinned MakeCell) it puts the
    # edge back where it was made (SoN::Serialize::JSON::_v1_consumers).
    my $EDGE_SEQ = 0;
    field $consumer_seq :reader = [];

    # Add a consumer to this node's consumer list
    method add_consumer($node) {
        push $consumers->@*, $node;
        push $consumer_seq->@*, ++$EDGE_SEQ;
    }

    # Remove a consumer from this node's consumer list
    method remove_consumer($node) {
        my $target_id = $node->id();
        my @keep = grep { $consumers->[$_]->id() ne $target_id } 0 .. $consumers->$#*;
        $consumer_seq->@* = $consumer_seq->@[@keep];
        $consumers->@* = $consumers->@[@keep];
    }

    # Abstract method - subclasses must implement
    method operation() {
        die ref($self) . " must implement operation()";
    }

    method class() {
        return $compat_class if defined $compat_class;
        return $self->operation();
    }

    # Serialize inputs to a list of ID strings for content_hash.
    # Handles undef, nested arrayrefs, and plain node inputs.
    method _serialize_inputs() {
        my @parts;
        for my $input ($self->inputs()->@*) {
            if (!defined $input) {
                push @parts, 'undef';
            } elsif (ref($input) eq 'ARRAY') {
                my @ids = map { defined($_) ? $_->id() : 'undef' } $input->@*;
                push @parts, '[' . join(',', @ids) . ']';
            } else {
                push @parts, $input->id();
            }
        }
        # (where wire v1 put it, so a node's id is what it was)
        push @parts, $mem_in->id() if $mem_operand;
        return @parts;
    }

    method content_hash() {
        return join('|', $self->operation(), $self->_serialize_inputs());
    }

    # Late-binding setter for the per-node scheduler interpretation.
    # Called by the scheduler as it walks the graph and decides what
    # surface syntax each control-affecting node should emit.
    method set_schedule_data($meta) {
        $schedule_data = $meta;
        return;
    }

    # Late-binding setter for the stamp (type-lattice hint carried from
    # B::SoN). A loop header Phi's stamp is only knowable after the body
    # walk computes the back-edge value's stamp, so the producer patches
    # it in post-construction, mirroring set_control_in/set_representation.
    method set_stamp($new_stamp) {
        $stamp = $new_stamp;
        return;
    }

    # Late-binding setter for the effect-chain predecessor.
    # Maintains the bidirectional use-def edge by adjusting consumer
    # registration on the old and new predecessors. Called by the
    # Block control-chain fixup pass in Perl::Actions when this node
    # appears as a statement-position side effect.
    method set_control_in($ctrl) {
        if (defined $control_in) {
            $control_in->remove_consumer($self);
        }
        $control_in = $ctrl;
        if (defined $ctrl) {
            $ctrl->add_consumer($self);
        }
        return;
    }

    # Late-binding setter for the machine-level representation.
    # Called by the IR builder or a lowering pass after the node is
    # constructed. Does not affect content_hash or hash-consing identity.
    method set_representation($repr) {
        $representation = $repr;
        return;
    }
}
