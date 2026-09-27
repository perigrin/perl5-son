# ABOUTME: two `my $m` in sibling blocks are two variables, and a store must key
# ABOUTME: its scope on the OP's pad index, not on a field of a hash-consed node.
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

# `PadAccess::content_hash` EXCLUDES `targ` ON PURPOSE -- the pad index is
# CV-local, so two reads of the same variable at different indices must be one
# node. That is right ACROSS units and wrong WITHIN one: two `my $m` in sibling
# blocks are two variables at two indices, and they hash-cons to a single node.
#
# The node is then the only thing a store has in hand, and `$target->targ`
# reads whichever index was recorded FIRST. Measured:
#
#     { my $m = "A"; print "got $m\n" }
#     { my $m = "B"; print "got $m\n" }
#
#     perl   got A / got B
#     before got A / got            <- and `$m` undeclared in the emission
#
# The second store bound pad slot 1 a second time, slot 5 stayed empty, and the
# read fell back to the bare PadAccess -- so `Constant "B"` never entered the
# graph at all. A silent wrong answer, not a refusal.
#
# The op's own targ is authoritative and already in hand: `$op->last` IS the
# target padsv. Measured, it reports 1 then 5 for the two blocks.
subtest 'two blocks, one name' => sub {
    my $src = <<'SRC';
{ my $m = "A"; print "got $m\n" }
{ my $m = "B"; print "got $m\n" }
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'each block reads its own variable'
        or diag $out;
};

# THE SAME SHAPE UNDER `if`, which is how perl's own t/base/rs.t hits it: six
# `else` arms each doing `my $msg = $@ || "Zombie Error"`. Five of the six read
# an undeclared `$msg`.
subtest 'two if-arms, one name' => sub {
    my $src = <<'SRC';
our $c = 1;
if ($c) { my $m = "A"; print "got $m\n" }
if ($c) { my $m = "B"; print "got $m\n" }
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'each arm reads its own variable'
        or diag $out;
};

# THREE, so a fix that merely swaps the FIRST and SECOND index is not enough.
subtest 'three blocks, one name' => sub {
    my $src = <<'SRC';
{ my $m = "A"; print "got $m\n" }
{ my $m = "B"; print "got $m\n" }
{ my $m = "C"; print "got $m\n" }
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'all three read their own variable'
        or diag $out;
};

# DIFFERENT NAMES ALREADY WORKED, and must keep working -- this is the control
# that says the fix is about the collision and not about pad stores generally.
subtest 'two blocks, two names' => sub {
    my $src = <<'SRC';
{ my $p = "A"; print "got $p\n" }
{ my $q = "B"; print "got $q\n" }
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'still right'
        or diag $out;
};

done_testing;
