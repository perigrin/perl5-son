# ABOUTME: a package scalar mutated in a loop body must carry across iterations;
# ABOUTME: it does not, and the emission silently writes the same value each pass.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub write_tmp ($src, $tag) {
    my $f = "$dir/$tag." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    return $f;
}

sub graph_of ($src) {
    my $f = write_tmp( $src, 'g' );
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    return eval { JSON::PP->new->decode($j) };
}

sub emit ($src) {
    my $data = graph_of($src) or return ( undef, 'no graph' );
    return ( undef, 'no program' ) unless $data->{methods}{'main::__PROGRAM__'};
    my $out = eval { SoN::Deparse->new->render($data) };
    return ( undef, ( $@ || 'refused' ) ) unless defined $out;
    return ( $out, undef );
}

sub runs ($src) {
    my $f = write_tmp( $src, 'r' );
    my $o = qx($^X $f 2>&1);
    unlink $f;
    return $o;
}

# A PAD SLOT'S READ RESOLVES THROUGH THE SCOPE BINDING, so re-pointing the slot
# at the loop header Phi (_patch_loop_phi) is enough -- the next read finds the
# Phi. A PACKAGE scalar's read does not: the gvsv handler builds a fresh
# memory-pinned EntryDef whenever the name is in _package_scalars_written(), so
# that a write in another sub is visible. Right for the cross-sub case, wrong
# inside a loop, where the value IS carried and the carrier is the Phi.
#
# The Phi is BUILT -- _scout_mutated_targs detects the stash key and has no
# pad-only filter -- and then nothing reads it. Measured:
#
#     our $n = 5;
#     foreach $t ($n..$n + 3) { print "ok $t\n"; $n++ }
#     print "end $n\n";
#
#     perl   ok 5 / ok 6 / ok 7 / ok 8 / end 9
#     ours   ok 5 / ok 6 / ok 7 / ok 8 / end 6
#
# because the body's increment reads the PRE-LOOP EntryDef, so the store writes
# 6 on every pass. A SILENT WRONG ANSWER, not a refusal -- which is why this is
# recorded as a failing expectation rather than left unmeasured.
#
# See docs/plans/2026-09-26-a-package-scalar-is-not-loop-carried.md for the two
# candidate owners of the carried value (the memory Phi or the value Phi) and
# why the choice has to be made deliberately.
todo 'a package scalar mutated in a loop body is not loop-carried' => sub {
    subtest 'a counter in a foreach body accumulates' => sub {
        my $src = <<'SRC';
our $n = 5;
foreach $t ($n..$n + 3) {
    print "ok $t # skipped\n";
    $n++;
}
print "end $n\n";
SRC
        my ( $out, $why ) = emit($src);
        ok defined $out, 'renders' or do { diag $why; return };
        is runs($out), runs($src), 'the counter reaches 9'
            or diag $out;
    };

    subtest 'a counter in a while body accumulates' => sub {
        my $src = <<'SRC';
our $n = 0;
my $i = 0;
while ($i < 3) {
    $n++;
    $i++;
}
print "n=$n\n";
SRC
        my ( $out, $why ) = emit($src);
        ok defined $out, 'renders' or do { diag $why; return };
        is runs($out), runs($src), 'the counter reaches 3'
            or diag $out;
    };
};

# THE PAD FORM IS THE CONTROL, and it must keep working: the same loop over a
# LEXICAL counter is loop-carried correctly today, which is what says the defect
# is about the package read path and not about loops.
subtest 'a lexical counter in a loop body still accumulates' => sub {
    my $src = <<'SRC';
my $n = 0;
my $i = 0;
while ($i < 3) {
    $n++;
    $i++;
}
print "n=$n\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'the lexical counter reaches 3'
        or diag $out;
};

done_testing;
