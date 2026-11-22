# ABOUTME: The exceptional way out of a node that may die (wire v2's `eval` profile): a control
# ABOUTME: node whose one input is that node; its value is the exception in flight.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

# What follows an Exc on the control chain runs only when its node died: the
# restores of the `local`s live there, then its eval's catch Region.
class SoN::IR::Node::Exc :isa(SoN::IR::Node) {
    method operation() { 'Exc' }
}

1;
