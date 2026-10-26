# ABOUTME: Reference constructor operation node in the Chalk IR.
# ABOUTME: Unary data node wrapping the \ operator.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node::UnaryOp;

class SoN::IR::Node::Ref :isa(SoN::IR::Node::UnaryOp) {
    # A REFERENCE TO EACH ELEMENT, not to the aggregate: `\(@a)` is perlref's
    # special case, the list (\$a[0], \$a[1], ...), and `\(%h)` likewise over
    # the values. The input is the aggregate; the node is a List whose length
    # is the aggregate's at runtime. In the content hash, since `\@a` and
    # `\(@a)` over one array are two different values.
    field $each :param :reader = 0;
    # `\$x` OF A `my` THAT A LOOP RENEWS EACH PASS: perl's \$x on each pass is
    # to that pass's variable. A consumer with one location per lexical refuses.
    field $fresh_each_pass :param :reader = 0;

    method operation() { 'Ref' }
    method op_str()    { '\\' }

    method content_hash() {
        return join('|', 'Ref', ($each ? 'each' : ()), ($fresh_each_pass ? 'fresh' : ()),
            $self->_serialize_inputs());
    }
}
