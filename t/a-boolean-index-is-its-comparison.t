# ABOUTME: `index(...) >= 0`, `!= -1`, `== -1` are one index op whose value perl makes a
# ABOUTME: boolean (OPpTRUEBOOL, OPpINDEX_BOOLNEG); B::SoN read the raw position instead.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use SoN::Deparse;

# THE DEFECT (found compiling stevan/curly's examples/brainfuck.pl): perl
# folds the comparison of `index(...) >= 0` (and `> -1`, `!= -1`, `== -1`)
# into the index op, flagged OPpTRUEBOOL (and OPpINDEX_BOOLNEG for `== -1`).
# The comparison op is gone, so the flags are the only place the test lives.
# `grep { index("ab", $_) >= 0 } ("a", "b", "x")` gave `b x` for `a b`:
# position 0 was false and -1 true.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub file ($src) { my $f = "$dir/p" . ++$n . '.pl'; open my $o, '>', $f or die $!; print $o $src; close $o; $f }
sub run_perl ($src) { my $f = file($src); scalar qx(/usr/bin/timeout 10 $^X $f 2>/dev/null) }
sub round_trips ($src) {
    my $f   = file($src);
    my $j   = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    my $d   = SoN::Deparse->new;
    my $out = $d->render( eval { JSON::PP->new->decode($j) } // {} );
    return fail("renders: $src") || diag( $d->gap // do { local ( @ARGV, $/ ) = "$dir/err"; <> } ) unless defined $out;
    is run_perl($out), run_perl($src), "round trips: $src" or diag $out;
}

round_trips($_) for
    'my @c = grep { index("ab", $_) >= 0 } ("a", "b", "x"); print "@c\n";',
    'my @c = grep { index("ab", $_) > -1 } ("a", "b", "x"); print "@c\n";',
    'my @c = grep { index("ab", $_) != -1 } ("a", "b", "x"); print "@c\n";',
    'my @c = grep { index("ab", $_) == -1 } ("a", "b", "x"); print "@c\n";',
    'my @c = grep { rindex("abca", $_) >= 0 } ("a", "c", "x"); print "@c\n";',
    'my $s = "ab"; print index($s, "a") >= 0 ? "y" : "n", index($s, "z") == -1 ? "y" : "n", "\n";',
    'my $s = "ab"; my $n = index($s, "b"); print "$n\n";';

done_testing;
