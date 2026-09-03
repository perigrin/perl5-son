# ABOUTME: Allocates a mutable heap cell holding a captured variable.
# ABOUTME: One node, one cell PER EXECUTION -- a loop body yields one per iteration.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

# A CAPTURE IS A SHARED MUTABLE CELL, NOT A VALUE. Measured on 5.42.0:
#
#     my $n=5; my $c = sub { $n }; $n = 99;      $c->() is 99  the VARIABLE
#     my $set = sub { $n = shift }; $set->(42)   outer $n is 42
#     my $c=0; $inc->(); $inc->();               $rd->() is 2  ONE cell shared
#
# so the VALUE cannot ride on AnonSub's inputs: that gives each closure a
# snapshot, correct for a read-only capture and wrong for all three above.
#
# inputs are [init_value, memory]; the node becomes the new memory version, so
# the allocation is ordered against other memory effects and the sharing is
# visible to the optimizer rather than implied.
#
# NEVER HASH-CONSED. Two structurally identical MakeCells are two DIFFERENT
# cells -- that is what makes `for my $i (1..3) { push @s, sub { $i } }` give
# 1,2,3 rather than 3,3,3. One node with three executions yields three cells.
#
# captured_written says whether ANY closure over this cell writes it. False
# lets a consumer skip the cell entirely and pass the value. The conservative
# direction is TRUE: claiming written when it is not costs performance, never
# correctness.
class SoN::IR::Node::MakeCell :isa(SoN::IR::Value) {
    my $cell_counter = 0;

    field $cell_name        :param :reader = undef;
    field $captured_written :param :reader = 0;
    field $cell_id          :reader;

    ADJUST { $cell_id = $cell_counter++; }

    method operation() { 'MakeCell' }

    # Identity is the ALLOCATION, not the contents. Including a counter is what
    # stops two identical allocations collapsing into one shared cell.
    method content_hash() {
        return join('|', 'MakeCell', "cell_id=$cell_id",
            $self->_serialize_inputs());
    }
}
