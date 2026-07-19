# ABOUTME: Producer-side side table carrying transitional per-node metadata
# ABOUTME: (is_stmt_effect, loop_control) that Chalk::IR::Node has no field for.

use v5.42.0;
use utf8;

package SoN::FromOptree::EffectMeta;

use Scalar::Util qw(refaddr);

# Chalk::IR::Node::Call/Assign/Print have no is_stmt_effect :param (adding
# one would either crash feature-class on an unknown :param or leak a
# transitional field into every downstream consumer of the merged type).
# FromOptree instead records this knowledge here, keyed by refaddr (never by
# content_hash or the node's own id string, so hash-consed lookalikes never
# collide), and SoN::Serialize::JSON consults it when emitting the
# is_stmt_effect/loop_control wire fields the Chalk loader already decodes.
# Slated for deletion once control moves to control_in at produce-time
# (plan Step 2) and this whole flattened-wire seam retires.
my %STMT_EFFECT;
my %LOOP_CONTROL;

sub mark_stmt_effect ($node) {
    $STMT_EFFECT{ refaddr($node) } = 1;
    return;
}

sub is_stmt_effect ($node) {
    return $STMT_EFFECT{ refaddr($node) } ? 1 : 0;
}

sub mark_loop_control ($node, $loop) {
    $LOOP_CONTROL{ refaddr($node) } = $loop;
    return;
}

sub loop_control_of ($node) {
    return $LOOP_CONTROL{ refaddr($node) };
}

1;
