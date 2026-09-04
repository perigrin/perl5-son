# ABOUTME: `write` is a CALL into the format CV in the glob's FORM slot.
# ABOUTME: It must never vanish -- it did once, and the graph looked healthy.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# `write` used to VANISH. enterwrite is registered with an undef node_type and
# no SKIP flag, so the generic branch built nothing and still returned
# 'handled' -- which also made the unknown-op warning unreachable, since that
# only fires for UNREGISTERED ops. The statement disappeared from the middle of
# a program while the statements around it compiled normally: the output looked
# healthy and was simply missing a line. That is a miscompile, not a GAP.
#
# IT IS A CALL ACROSS CVs, and that structure is now what lowers it. A format
# is compiled into a CV parked in the glob's FORM slot (a B::FM, which isa
# B::CV, whose ROOT op is `leavewrite` -- the format's own root, exactly as
# leavesub roots an ordinary sub), so enterwrite and leavewrite are the two
# halves of one call rather than a bracketed region in one optree. The body is
# registered under a deterministic name and `write` becomes a Call naming it,
# the same addressing an anon sub uses.

sub translate_program ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

subtest 'write becomes a call, and never vanishes' => sub {
    my $graph;
    ok(lives {
        $graph = translate_program(q{
            sub {
                format STDOUT =
@<<<
"hi"
.
                write;
                print "after\n";
            }
        });
    }, 'it lowers') or diag($@);
    return unless $graph;

    # THE REGRESSION THIS FILE EXISTS FOR: `write` once VANISHED. enterwrite
    # was registered with an undef node_type and no SKIP flag, so the generic
    # branch built nothing and still returned 'handled' -- the statement
    # disappeared from the middle of a program while everything around it
    # compiled, so the output looked healthy and was simply missing a line.
    # Whatever else changes, a write must leave a node behind.
    my ($call) = grep {
        $_->operation eq 'Call' && (($_->name // '') =~ /__FORMAT__/)
    } $graph->nodes->@*;
    ok($call, 'the write is a Call naming a format body -- not dropped');

    # The statement AFTER it must still be there: a fix that swallowed the
    # rest of the CV would also pass a "did not vanish" check on the write.
    ok(scalar(grep { $_->operation eq 'Print' } $graph->nodes->@*),
        'the following print survives too');
};

subtest 'ops that correctly build no node are untouched' => sub {
    # The refusal is keyed by an explicit list, NOT inferred from "undef
    # node_type and no SKIP flag". That shape also covers ops which build
    # nothing because a structural handler owns the construct; treating the
    # table's shape as a semantic fact conflates the two and breaks these.
    ok(lives { translate_program('sub { my $x = 0; try { $x = 1 } catch ($e) { $x = 2 } $x }') },
        'try/catch still translates (poptry builds no node, correctly)');

    ok(lives { translate_program('sub { my $t = 0; for my $i (1..3) { $t += $i } $t }') },
        'loops still translate (enterloop/leaveloop/iter build no node)');

    ok(lives { translate_program('sub { my $o = bless {}, "X"; $o->can("y") ? 1 : 0 }') },
        'method dispatch still translates');
};

done_testing;
