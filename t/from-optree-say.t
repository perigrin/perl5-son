# ABOUTME: `say` desugars to the SAME Print node as `print`, with a "\n" operand
# ABOUTME: appended — one operator downstream, not a second effect node.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $cerr = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $cerr" if $cerr;
    return SoN::FromOptree->translate($cv);
}

sub nodes_of ($g, $op) { grep { $_->operation eq $op } $g->nodes->@* }

# ---------------------------------------------------------------------------
# `say` is `print` plus a trailing newline. Desugaring it at the build site
# rather than giving it its own node means every downstream consumer -- the
# control pin, the arm-effect predicates, the backend's _lower_print -- sees one
# operator and needs no `say` case. Its OpMap entry maps it to a generic Call,
# which the print branch pre-empts.
# ---------------------------------------------------------------------------

subtest 'say builds a Print, not a Call' => sub {
    my $g = translate('sub { say "hi" }');
    my ($print) = nodes_of($g, 'Print');
    ok($print, 'a Print node is built') or return;

    my @calls = grep { ($_->name // '') eq 'say' } nodes_of($g, 'Call');
    is(scalar @calls, 0, 'no generic Call(say) survives');
};

subtest 'the newline is an appended operand' => sub {
    my $g = translate('sub { say "hi" }');
    my ($print) = nodes_of($g, 'Print');
    my @in = $print->inputs->@*;
    is(scalar @in, 2, 'say "hi" has two operands');
    is($in[0]->value, 'hi',  'the first is the argument');
    is($in[1]->value, "\n",  'the second is the newline');
};

subtest 'say LIST appends exactly one newline' => sub {
    my $g = translate('sub { say "a", "b", "c" }');
    my ($print) = nodes_of($g, 'Print');
    my @in = $print->inputs->@*;
    is(scalar @in, 4, 'three arguments plus one newline');
    is($in[-1]->value, "\n", 'the newline is last');
};

subtest 'print is unchanged — no newline is invented' => sub {
    my $g = translate('sub { print "hi" }');
    my ($print) = nodes_of($g, 'Print');
    my @in = $print->inputs->@*;
    is(scalar @in, 1, 'print "hi" has exactly one operand');
    is($in[0]->value, 'hi', '... the argument, with nothing appended');
};

subtest 'say is control-pinned, like print' => sub {
    # The stdout effect must be ordered and survive DCE.
    my $g = translate('sub { say "a"; say "b"; 1 }');
    my @prints = nodes_of($g, 'Print');
    is(scalar @prints, 2, 'both says survive as distinct effects');
    ok(defined $_->control_in, 'each is control-pinned') for @prints;
};

subtest 'say to an explicit filehandle GAPs' => sub {
    # Same refusal as print: the runtime-free backend writes only to stdout, so
    # honouring a handle would misroute rather than fail.
    my $err = dies { translate('sub { say STDOUT "x" }') };
    like($err, qr/GAP:/, 'refused');
    like($err, qr/explicit filehandle/, '... naming the filehandle form');
};

done_testing;
