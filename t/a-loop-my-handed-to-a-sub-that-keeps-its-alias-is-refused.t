# ABOUTME: A `my` made anew each pass of a loop, handed to a sub that may return or keep `\$_[0]`, is
# ABOUTME: refused by name: the wire keeps one slot for every pass (`3,3,3` for perl's `1,2,3`).
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub err_of ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>&1 >/dev/null);
}

# (found beside audit 4's X1: probes x/xm24, x/xm25)
my $GAP = qr/GAP: a `my` made anew each pass, handed to a sub that may return or keep a reference to it, is not yet lowered/;
for my $src (
    'sub k { \$_[0] } my @r; for my $i (1..3) { my $x = $i; push @r, k($x) } print join(",", map { $$_ } @r), "\n";',
    'our @K; sub keep { push @K, \$_[0] } for my $i (1..3) { my $x = $i; keep($x) } print join(",", map { $$_ } @K), "\n";',
    'sub k { \$_[0] } my @r; my @a = (1,2); for (@a) { my $x = $_; push @r, k($x) } print join(",", map { $$_ } @r), "\n";',
) {
    like err_of($src), $GAP, "refused by name: $src";
}
# (a callee that keeps no alias of its argument: nothing outlives the pass)
for my $src (
    'sub twice { $_[0] * 2 } my @r; for my $i (1..3) { my $x = $i; push @r, twice($x) } print "@r\n";',
    'sub bump { $_[0]++ } for my $i (1..3) { my $x = $i; bump($x); print $x } print "\n";',
) {
    unlike err_of($src), qr/GAP/, "not refused: $src";
}
done_testing;
