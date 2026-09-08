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

# A RUNTIME ARRAYREF IS THE SAME READ. It "cannot be statically flattened",
# which was true and was not the question: a deref READS the referent, and a
# read does not need its contents known at compile time. It is a PostfixDeref
# carrying the sigil and a memory input, the same node `$$r` already used.
#
# The flatten it replaced was itself unsound where it DID apply -- substituting
# an ArrayRef's construction-time elements loses every mutation between
# construction and deref (`my $r=[1,2]; $r->[0]=9; @$r` gave "1 2" for perl's
# "9 2"). See t/from-optree-deref-is-a-memory-read.t.
subtest 'rv2av over a non-literal ref in list context lowers' => sub {
    my $sub = sub { my ($r) = @_; my @b = @$r; scalar @b };
    my $graph;
    ok(lives { $graph = SoN::FromOptree->translate($sub) },
        'a runtime-ref deref lowers') or diag($@);
    ok(defined $graph, 'got a graph') or return;

    my ($deref) = grep { $_->operation eq 'PostfixDeref' } $graph->nodes->@*;
    ok defined $deref, 'it is a PostfixDeref' or return;
    is $deref->sigil, '@', '... carrying the array sigil';
};

done_testing;
