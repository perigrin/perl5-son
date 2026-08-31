# ABOUTME: Backticks yield a Str in scalar context and a List in list context;
# ABOUTME: one node serves both, so the stamp comes from the op, not a table.
use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub backtick_stamp ($code) {
    my ($n) = grep { $_->operation eq 'BacktickExpr' } graph_of($code)->nodes->@*;
    return undef unless $n;
    return $n->stamp ? $n->stamp->type : 'Unknown';
}

# WHY THIS IS NOT A %RESULT_STAMP ENTRY. Backticks are CONTEXT-SENSITIVE:
#
#     my $x = `cmd`;   one string
#     my @x = `cmd`;   the output split into lines
#
# perl marks the difference on the op itself (sK/1 vs lK/1) and ONE
# BacktickExpr node serves both -- list context wraps it in an ArrayRef
# afterwards. %RESULT_STAMP is keyed by NODE TYPE and _result_stamp never sees
# the op, so a fixed rule there would be right for one context and wrong for
# the other. The stamp is read at the construction site, where the op is in
# hand.
#
# It reached the wire Unknown before this: 1 of the 13 remaining Unknowns
# across perl's t/base, and the only one of them that was a genuine missing
# result type rather than a design question about where per-builtin results
# should live (176 builtins collapse to one generic Call node, which has no
# per-name slot in TypeLibrary).
subtest 'scalar context yields Str' => sub {
    is(backtick_stamp('sub { my $x = `echo hi`; $x }'), 'Str',
        'a scalar backtick is one string');
};

subtest 'list context yields List' => sub {
    is(backtick_stamp('sub { my @x = `echo hi`; @x }'), 'List',
        'a list backtick is the output split into lines');
};

# THE TWO MUST DIFFER. Asserting each alone would pass if both were stamped the
# same, which is exactly the bug a fixed table entry would introduce.
subtest 'the two contexts are distinguishable' => sub {
    isnt(backtick_stamp('sub { my $x = `echo hi`; $x }'),
         backtick_stamp('sub { my @x = `echo hi`; @x }'),
        'scalar and list backticks do NOT carry the same stamp');
};

subtest 'neither context reaches the wire Unknown' => sub {
    isnt(backtick_stamp('sub { my $x = `echo hi`; $x }'), 'Unknown',
        'scalar is typed');
    isnt(backtick_stamp('sub { my @x = `echo hi`; @x }'), 'Unknown',
        'list is typed');
};

done_testing;
