# ABOUTME: A point on the program's control chain where the statements change package --
# ABOUTME: where a `package` or `class` block's own statements begin or end.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::Node;

# THE PACKAGE THE FOLLOWING STATEMENTS RAN IN, as perl records it on each
# statement (the nextstate's stash). A class or package block's own
# statements -- `our %X = ...` in a class body -- run at the point the block
# stands, in its package; without this mark a consumer could only emit them
# at file level in main, spelling every such variable fully qualified.
# Placed on the program graph only, and only where the package changes.
class SoN::IR::Node::PackageMark :isa(SoN::IR::Node) {
    field $package :param :reader;

    method operation() { 'PackageMark' }
}
