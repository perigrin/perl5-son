# ABOUTME: A single-branch `if` whose arm TERMINATES (die/exit) must build real control flow.
# ABOUTME: Dropping the guard silently runs the arm's successor and returns the wrong status.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub program_graph ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    return $data->{methods}{'main::__PROGRAM__'};
}

sub ops_of ($g) {
    return map { $_->{op} . ($_->{fields}{name} // '') } $g->{nodes}->@*;
}

# A `die`/`exit` inside a single-branch `if` (NO else) is a control path that
# does not rejoin. The void-branch gate keys on _arm_has_element_store and
# _arm_has_void_call, and an arm whose only content is a TERMINATOR is neither
# -- so no If node was built at all, the terminator was left off the control
# chain, and the statement after the `if` ran unconditionally.
#
# Measured before the fix, `my @a=(1); say 1; if (scalar @a) { exit 4 } say 2;`
#   perl  : "1\n"    exit 4
#   chalk : "1\n2\n" exit 0
# Wrong stdout AND wrong status, with no diagnostic. `die` in the same shape had
# the identical defect and predates `exit` lowering entirely.
#
# An if/ELSE with a die arm already worked (corpus control-flow T2), which is
# what made this look covered.
for my $case (
    ['exit in a single-branch if' => "use 5.42.0;\nmy \$c = 1;\nsay 1;\nif (\$c) { exit 4 }\nsay 2;\n"],
    ['die in a single-branch if'  => "use 5.42.0;\nmy \$c = 1;\nsay 1;\nif (\$c) { die qq{b\\n} }\nsay 2;\n"],
    ['exit as a statement modifier' => "use 5.42.0;\nmy \$c = 1;\nsay 1;\nexit 4 if \$c;\nsay 2;\n"],
    ['die as a statement modifier'  => "use 5.42.0;\nmy \$c = 1;\nsay 1;\ndie qq{b\\n} if \$c;\nsay 2;\n"],
) {
    my ($name, $src) = @$case;
    subtest $name => sub {
        my $g = program_graph($src);
        ok($g, 'produced an entry graph') or return;

        my @ops = ops_of($g);
        # The guard must survive: either as real control flow (an If), or as a
        # loud GAP (no graph at all). What must NOT happen is a graph with the
        # terminator present but no branch -- that is the silent miscompile.
        my $has_if   = grep { $_ eq 'If' } @ops;
        my $has_term = grep { $_ eq 'Callexit' || $_ eq 'Unwind' } @ops;

        ok($has_if || !$has_term,
            'the guard is modelled (an If exists) or the case GAPs -- never a '
          . 'terminator with no branch')
            or diag('ops: ' . join(' ', @ops));
    };
}

# The BILATERAL partner: a void-call arm (no terminator) already worked and must
# keep working. Without this, "GAP on every single-branch if" would pass the
# cases above while breaking the shape the void-branch gate exists to serve.
subtest 'a void-call arm still builds control flow' => sub {
    my $g = program_graph("use 5.42.0;\nmy \$c = 1;\nsay 1;\nif (\$c) { say 9 }\nsay 2;\n");
    ok($g, 'produced an entry graph') or return;
    my @ops = ops_of($g);
    ok(scalar(grep { $_ eq 'If' } @ops), 'the void-call arm still builds an If')
        or diag('ops: ' . join(' ', @ops));
};

done_testing;
