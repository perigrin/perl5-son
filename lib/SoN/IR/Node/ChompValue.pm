# ABOUTME: The value chomp/chop yields -- the count chomp removed, or the character chop removed.
# ABOUTME: Distinct from the trimmed string, which is the Chomp itself.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Value;

# A chomp HAS TWO RESULTS AND THEY ARE NOT THE SAME VALUE, the split
# TransliterateCount makes for tr///. The Chomp rebinds its subject to the
# trimmed string; the EXPRESSION yields what was removed. Measured on 5.42.0:
#
#     my $k = "ab";   chop $k     ->  "b"
#     my $k = "ab\n"; chomp $k    ->  1
#
# Its one input is the subject BEFORE the trim: what was removed is a function
# of that string (and $/) alone, so a consumer can compute it from a copy
# without running the trim a second time.
class SoN::IR::Node::ChompValue :isa(SoN::IR::Value) {
    field $kind :param :reader = 'chomp';

    method operation() { 'ChompValue' }

    method content_hash() {
        return join('|', 'ChompValue', "kind=$kind", $self->_serialize_inputs());
    }
}
