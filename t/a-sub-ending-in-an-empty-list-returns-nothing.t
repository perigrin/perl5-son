# ABOUTME: A sub whose last statement is `()` returns the empty list, not what an earlier
# ABOUTME: statement left on the simulated stack (`sub g { $x++; () }` returned the increment).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use SoN::Deparse;

# THE DEFECT (found by chalk's agent, probe xxt05): `my $x = 1; sub g { $x++;
# () } my @l = (5, g(), 6)` printed `5 2 6` for perl's `5 6`. `()` compiles to
# a `stub`, which pushes nothing; the leavesub took the void `$x++`'s value,
# left on the simulated stack, as the sub's value. The wire was the one of
# `sub g { ++$x }`.

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
    'my $x = 1; sub g { $x++; () } my @l = (5, g(), 6); print "@l\n";',
    'my $x = 1; sub g { $x = 7; () } my @l = (5, g(), 6); print "@l $x\n";',
    'sub g { my $y = 3; () } my @l = (g(), g()); print scalar(@l), "\n";',
    'our $x = 1; sub g { $x++; () } my $n = () = g(); print "$n $x\n";';

done_testing;
