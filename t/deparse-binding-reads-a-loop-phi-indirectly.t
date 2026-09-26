# ABOUTME: A binding whose value reaches a loop Phi THROUGH a pure node must be
# ABOUTME: placed after the loop too -- the search has to be transitive.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub run_perl ($src) {
    my $f = "$dir/r." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $f 2>&1);
    unlink $f;
    return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
    unlink $f;
    return ( eval { JSON::PP->new->decode($j) }, $e );
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my ( $data, $err ) = graph_of($src);
    unless ( $data && $data->{methods}{'main::__PROGRAM__'} ) {
        fail "$name: translates";
        diag $err;
        return;
    }
    my $d   = SoN::Deparse->new;
    my $out = eval { $d->render($data) };
    unless ( defined $out ) {
        my $g = $d->gap // $@ // '(no reason)';
        $g =~ s/\n.*//s;
        fail "$name: renders";
        diag $g;
        return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# THE SEARCH WAS ONE LEVEL DEEP. The prologue holds a binding back when one of
# its DIRECT inputs is a Phi whose region is a Loop -- correct, and insufficient,
# because a pure node between them hides the Phi. Measured on
# `for my $n (1..3) { my @q = (1..$n) }`:
#
#     8  Phi          in=[7,17] region=2     the induction variable
#     12 Range        in=[7,8]                reads the Phi
#     13 ArrayLiteral in=[12]                 reads the Range -- one level down
#
# so `@q`'s binding saw no Phi among its inputs, went into the prologue, and was
# emitted ABOVE the loop:
#
#     my @q = (((1) .. ($phi16)));     <- before $phi16 is declared
#     my $phi16 = 1;
#     while ((4 > $phi16)) { ... }
#
# printing `0 0 0` where perl prints `1 2 3`. The graph was correct throughout;
# only the placement was wrong, which is why this is a scheduling rule rather
# than anything about ranges.

# ATTEMPTED AND REVERTED 2026-09-26. Two facts established, and the second is
# why the obvious fix is wrong.
#
# 1. THE PLACEMENT SEARCH IS ONE LEVEL DEEP, in two places. A binding is held
#    back from the prologue when a DIRECT input is a loop Phi (the pad path) or
#    a chain-bound effect (the aggregate path at Deparse.pm:652). Neither sees
#    through a pure node, so the ArrayLiteral for `@q` saw only the Range.
#
# 2. BUT DEFERRING TO THE LOOP'S JOIN IS ALSO WRONG. Making the search
#    transitive and pushing onto %after_region moved the emission from above the
#    loop to BELOW it:
#
#      my $phi16 = 1;
#      while ((4 > $phi16)) { push(@sizes, scalar(@q)); ... }
#      my @q = (((1) .. ($phi16)));      <- still wrong
#
#    because `@q` is READ INSIDE THE BODY. The binding belongs in the body,
#    before its reader, and %after_region places things after the loop has
#    closed -- the right destination for a value that only settles then, and the
#    wrong one for a value the body itself consumes.
#
# So the fix needs a placement no mechanism currently provides: inside the loop
# body, ahead of the reader. Reverted rather than shipped, because moving a
# defect from one wrong line to another wrong line is not progress and the
# emission still prints `0 0 0` where perl prints `1 2 3`.
#
# The three cases below that PASS are kept as guards: whatever builds
# body-internal placement must not disturb them.
{
    my $todo = todo 'the binding belongs inside the loop body before its reader; no placement mechanism does that yet';
round_trips( <<'SRC', 'a binding reaching a loop Phi through a Range' );
my @sizes;
for my $n (1 .. 3) {
    my @q = (1 .. $n);
    push @sizes, scalar(@q);
}
print "@sizes\n";
SRC

}

round_trips( <<'SRC', 'through arithmetic rather than a Range' );
my @sizes;
for my $n (1 .. 3) {
    my $doubled = $n * 2;
    push @sizes, $doubled;
}
print "@sizes\n";
SRC

# A DIRECT PHI READ MUST STILL WORK -- it is the case the one-level search was
# written for and is the regression guard.
round_trips( <<'SRC', 'a binding reading the loop Phi directly' );
my @seen;
for my $n (1 .. 3) {
    push @seen, $n;
}
print "@seen\n";
SRC

# AND A GENUINELY LOOP-INVARIANT BINDING MUST STILL HOIST. If the transitive
# search is too eager it will hold back a value that does not read the loop at
# all, which is a placement change with no cause.
round_trips( <<'SRC', 'a loop-invariant binding is unaffected' );
my $base = 10;
my @out;
for my $n (1 .. 3) {
    push @out, $base;
}
print "@out\n";
SRC

done_testing;
