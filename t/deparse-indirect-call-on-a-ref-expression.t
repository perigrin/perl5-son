# ABOUTME: `->` binds tighter than `\`, so an indirect call whose callee is a
# ABOUTME: reference EXPRESSION must parenthesise it or the arrow lands inside.
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

sub emit ($src) {
    my $f = write_tmp( $src, 'g' );
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    my $data = eval { JSON::PP->new->decode($j) } or return ( undef, 'no graph' );
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

# `->` BINDS TIGHTER THAN `\`. Measured, perl's own deparse of
# `\(&twice)->(21)`:
#
#     my $x = \&twice->(21);
#
# -- the arrow is INSIDE the reference. So that spelling calls `&twice` with no
# arguments (the `&` form inherits @_, which is empty), then calls its RESULT as
# a code ref:
#
#     sub twice { defined $_[0] ? $_[0]*2 : "UNDEF-ARG" }
#     \(&twice)->(21)   Undefined subroutine &main::UNDEF-ARG called
#
# The corpus showed it as `Undefined subroutine &main::0` -- the `0` being what
# `$_[0] * 2` computes from an undef argument. Two cases died that way, which is
# why it read as a missing sub rather than as a precedence defect.
#
# The reference itself is not the problem: `\(&twice)` IS a CODE ref and
# `(\(&twice))->(21)` returns 42. Only the unparenthesised juxtaposition breaks.

subtest 'an indirect call through a code-ref expression' => sub {
    my $src = <<'SRC';
sub twice { $_[0] * 2 }
my $r = (\&twice)->(21);
print "$r\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };

    my $f = write_tmp( $out, 'c' );
    my $chk = qx($^X -c $f 2>&1);
    unlink $f;
    like $chk, qr/syntax OK/, 'the emission compiles' or diag "$chk\n$out";

    is runs($out), runs($src), 'and it prints what perl prints' or diag $out;
};

# A BARE VARIABLE CALLEE MUST NOT GROW PARENS it does not need -- that is the
# ordinary shape and the regression guard for this fix.
subtest 'a plain code-ref variable still calls directly' => sub {
    my $src = <<'SRC';
sub twice { $_[0] * 2 }
my $ref = \&twice;
my $r = $ref->(21);
print "$r\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'round-trips' or diag $out;
};

done_testing;
