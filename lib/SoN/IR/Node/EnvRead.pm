# ABOUTME: Environment-variable read ($ENV{KEY}) in the SoN IR graph.
# ABOUTME: key = the compile-time env-var name; lowers to the host C getenv.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::IR::Node::EnvRead :isa(SoN::IR::Node) {
    field $key :param :reader;

    method operation () { 'EnvRead' }

    method content_hash () {
        # Env writes are not modelled, so a read is constant per process and
        # two reads of the same key hash-cons to one node.
        return "EnvRead|key=$key";
    }
}

1;
