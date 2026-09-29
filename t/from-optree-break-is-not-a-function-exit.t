# ABOUTME: a `last` leaves the LOOP; a `return` leaves the FUNCTION.
# ABOUTME: one signal string for both left every consumer unable to tell them apart.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir( CLEANUP => 1 );

use SoN::Deparse;

sub run_perl ($src) {
    my $f = "$dir/r." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>&1);
    unlink $f;
    return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>$dir/err);
    my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
    unlink $f;
    return ( eval { JSON::PP->new->decode($j) }, $e );
}

# THE TWO TRANSFERS ARE NOT THE SAME. A `return` leaves the function and needs
# an exits list to record its control edge; a `last` leaves the LOOP and routes
# through @break_projs to the exit Region. _walk_branch signalled both as
# 'exited', so a consumer reading that string could only guess -- and the
# statement-modifier handler, which can lower neither without its own list,
# refused both alike.
#
# This is a defect introduced by the branch-arm break work (21776e8), not a
# pre-existing one: before it, a `last` in an arm was refused outright and
# never produced a signal at all.
subtest 'a break in an arm and a return in an arm are different edges' => sub {
    my ( $brk, $brk_err ) = graph_of( <<'SRC' );
my @o = ("A", "HIT", "C");
my $n = 0;
foreach (@o) { $n++; if ($_ eq "HIT") { last } }
print "$n\n";
SRC
    ok $brk, 'the break form translates' or diag($brk_err);

    # THE RETURN LEAVES THE SUB, not just the loop: read as a break, `f`
    # would fall out and return 0 where perl returns 4.
    my $src = <<'SRC';
sub f {
    for my $i (1..9) { if ($i == 4) { return $i } }
    return 0;
}
print f(), "\n";
SRC
    my ( $ret, $ret_err ) = graph_of($src);
    ok $ret, 'the return form translates' or diag($ret_err);
    my $out = $ret && SoN::Deparse->new->render($ret);
    is run_perl($out // ''), run_perl($src), '... and returns 4 as perl does'
        or diag $out;
};

# A BREAK MUST NOT REACH A FUNCTION-EXIT CONSUMER. The value-arm handlers
# (short-circuit RHS, cond_expr) refuse an exiting arm because a value arm
# that leaves has no value to contribute -- true of a return, and equally
# true of a break, so both must refuse there rather than one being mistaken
# for the other.
subtest 'a break inside a value arm still refuses' => sub {
    my ( undef, $err ) = graph_of( <<'SRC' );
my $s = 0;
for my $i (1..9) { my $v = ($i > 2) ? do { last } : $i; $s += $v }
print "$s\n";
SRC
    like $err, qr/GAP:/, 'it is refused rather than mislowered';
};

done_testing;
