# ABOUTME: Tests SoN::FromOptree refuses `write` loudly instead of dropping it.
# ABOUTME: A format is a separate CV in the glob's FORM slot; enterwrite is a call into it.

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
# It cannot be compiled today for a structural reason: a format is compiled
# into a CV parked in the glob's FORM slot (a B::FM, which isa B::CV, whose
# ROOT op is `leavewrite` -- the format's own root, exactly as leavesub roots
# an ordinary sub). enterwrite and leavewrite are therefore the two halves of a
# call ACROSS CVs, not a bracketed region within one optree, which is why only
# enterwrite appears at the call site. Compiling it needs that second body
# walked plus the formline accumulator.

sub translate_program ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

subtest 'write is refused by name, not silently dropped' => sub {
    my $err = dies {
        translate_program(q{
            sub {
                format STDOUT =
@<<<
"hi"
.
                write;
                print "after\n";
            }
        });
    };

    ok($err, 'translation refuses rather than returning a graph');
    like($err, qr/GAP/, 'refusal is a GAP');
    like($err, qr/\bwrite\b/,
        'names the construct the user wrote');
    unlike($err, qr/enterwrite/,
        'does NOT leak the op name -- enterwrite is perl bookkeeping');
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
