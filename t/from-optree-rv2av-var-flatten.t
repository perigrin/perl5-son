# ABOUTME: Tests SoN::FromOptree flattens `my @b = @$r` (rv2av over a variable
# ABOUTME: bound to a literal ArrayRef) in list context; GAPs a runtime ref. zhi 019f5e42.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;

# `my $r=[1,2,3]; my @b=@$r` derefs an arrayref VARIABLE in list context. The
# rv2av-flatten path only fired when its kid was a `const` (const-range). Over a
# padsv bound to a literal ArrayRef the elements must flatten too, or the
# trailing aassign wraps the single ArrayRef as ONE element and `scalar @b`
# returns 1 -- a silent miscompile. The end-to-end behavior (lli == perl == 3)
# is pinned by the chalk corpus gate (variables.md A12); here we assert the
# producer flattens (does not GAP) a literal-arrayref deref.
subtest 'my @b = @$r flattens a literal-arrayref variable (no GAP)' => sub {
    my $sub = sub { my $r=[1,2,3]; my @b=@$r; scalar @b };
    my $graph;
    ok(lives { $graph = SoN::FromOptree->translate($sub) },
        'translate lives on a literal-arrayref deref') or diag($@);
    ok(defined $graph, 'got a graph');
};

# A runtime arrayref (`@$r` where $r is a computed ref, not a literal ArrayRef
# node in the graph) cannot be statically flattened. Rather than leave the
# single ref as one element (silent miscompile), GAP loudly.
subtest 'rv2av over a non-literal ref in list context GAPs (not silent)' => sub {
    my $sub = sub { my ($r) = @_; my @b = @$r; scalar @b };
    ok(!lives { SoN::FromOptree->translate($sub) },
        'a runtime-ref deref-flatten GAPs') or diag('expected a GAP, got a graph');
    like($@, qr/GAP/i, 'the die is a loud GAP') or diag("actual: $@");
};

done_testing;
