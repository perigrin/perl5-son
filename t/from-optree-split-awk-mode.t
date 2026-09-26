# ABOUTME: `split " "` is AWK MODE -- leading whitespace stripped, runs collapsed
# ABOUTME: -- and `split / /` is a literal one-space pattern. PMf_SKIPWHITE says which.
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

# TWO PROGRAMS, ONE SPELLING AWAY. Measured on `"  a b "`:
#
#     split / /, ...   4 fields, ["", "", "a", "b"] -- a literal single space
#     split " ", ...   2 fields, ["a", "b"]         -- awk mode
#
# awk mode strips LEADING whitespace and splits on RUNS. It is not the pattern
# `/ /` and it is not `/\s+/` either -- only the leading-strip makes it awk.
#
# THE OPTREE SAYS WHICH, in a bit B::Concise does not print. Measured, the split
# op's pmflags:
#
#     split / /, ...       pmflags=0
#     split " ", ...       pmflags=2048     PMf_SKIPWHITE
#     my $p=" "; split($p) pmflags=2048
#
# So it is a COMPILE-TIME fact even for a runtime pattern: perl sets the bit
# whenever the pattern is a plain string expression rather than a `//` literal.
# Both forms reached the producer as `split(qr{ }, ...)` -- the bit was dropped
# and the emission silently computed a different answer.

subtest 'awk mode strips leading whitespace' => sub {
    my $src = <<'SRC';
my @a = split(" ", "  a b ");
print scalar(@a), " [@a]\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'two fields, no leading empties' or diag $out;
};

# A RUNTIME PATTERN STILL REFUSES, for an unrelated and pre-existing reason:
# `$op->precomp` is undef when the pattern is not a compile-time literal, so
# there is nothing to emit. Asserted as a REFUSAL rather than left out, because
# the awk bit IS set on this op (measured, pmflags=2048) and a later fix to the
# interpolated-pattern GAP must not quietly lose it -- the refusal is what
# stands between here and a wrong answer.
subtest 'a runtime string pattern refuses, and says why' => sub {
    my $src = <<'SRC';
my $p = " ";
my @a = split($p, "  a b ");
print scalar(@a), " [@a]\n";
SRC
    my $f = write_tmp( $src, 'g' );
    my $err = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>&1 >/dev/null);
    unlink $f;
    like $err, qr/runtime-interpolated pattern/,
        'refused on the pattern, not silently mis-split' or diag $err;
};

# A `//` PATTERN IS NOT AWK MODE, and this is the regression guard: turning
# every single-space split into awk mode would lose the leading empty fields
# that `split / /` is defined to produce.
subtest 'a single-space pattern keeps its empty fields' => sub {
    my $src = <<'SRC';
my @a = split(/ /, "  a b ");
print scalar(@a), " [@a]\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'four fields, two of them empty' or diag $out;
};

done_testing;
