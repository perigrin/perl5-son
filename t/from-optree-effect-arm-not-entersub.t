# ABOUTME: A void branch arm holding an effect that is NOT an entersub must still build control flow.
# ABOUTME: warn/push/chdir/close were invisible to the arm scan, so their guard was silently dropped.

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

# _arm_has_void_call asks "is this arm an ENTERSUB in void context". The question
# it needs to answer is "does this arm hold an EFFECT that must be control-pinned".
# Those diverged: warn, push, chdir and close are named ops, not entersub, so the
# scan walked past them, no If was built, and the effect landed on the base
# control chain to fire unconditionally.
#
# die and print escaped only because each has its OWN detector (_arm_has_die, and
# the print/say test inside the scan) -- which is why this looked covered.
#
# Measured before the fix on `my $ok = 1; $ok or warn "W\n"; print "end\n";`
#   perl  : "end\n"            warn does not fire, $ok is true
#   graph : Print control_in=0, Call control_in=0, NO If node
# The warn shares Start with the print. The guard is not weakened, it is absent.
#
# The build path already pins these ops correctly ($void_effect_call, which is
# why the Call exists at all). Only the ARM SCAN was stale.
for my $case (
    ['warn in a void or-arm'  => 'warn "W\n"'],
    ['push in a void or-arm'  => 'push @g, 9'],
    ['chdir in a void or-arm' => 'chdir "/"'],
    ['close in a void or-arm' => 'close STDIN'],
    # The two that always worked, kept so a fix cannot regress them.
    ['die in a void or-arm'   => 'die "D\n"'],
    ['print in a void or-arm' => 'print "P\n"'],
) {
    my ($label, $effect) = $case->@*;
    my $g = program_graph(
        "our \@g;\nmy \$ok = 1;\n\$ok or $effect;\nprint qq{end\\n};\n");
    ok defined $g, "$label: graph built" or next;

    my @ops = map { $_->{op} } $g->{nodes}->@*;
    ok scalar(grep { $_ eq 'If' } @ops),
        "$label: the guard builds an If";
}

done_testing;
