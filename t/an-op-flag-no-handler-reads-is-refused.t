# ABOUTME: An op carrying a memory flag (OPpTARGET_MY, a `local`'s OPpLVAL_INTRO, ...) that no handler
# ABOUTME: reads is refused by name (fifth final audit, Q1 and Q8); `$t = "$s$s"` stores into $t.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use SoN::Deparse;

# THE DEFECTS. `my $s = "a"; $s = "$s$s"` printed `a` for perl's `aa`: before
# the peephole pass the tree is a `stringify` with OPpTARGET_MY over a concat,
# and the stringify handler pushed a Coerce and never read the flag (Q1).
# `local ${"x"} = 2` stored with no save and no restore (Q8): no handler read
# the OPpLVAL_INTRO. Each rule closed only the shapes it listed; the check is
# now one place, in _step, by flag.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub file ($src) { my $f = "$dir/p" . ++$n . '.pl'; open my $o, '>', $f or die $!; print $o $src; close $o; $f }
sub stderr_of ($src) { my $f = file($src); scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>&1 >/dev/null) }
sub run_perl ($src) { my $f = file($src); scalar qx(/usr/bin/timeout 10 $^X $f 2>/dev/null) }

sub round_trips ($src) {
    my $f    = file($src);
    my $j    = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    my $d    = SoN::Deparse->new;
    my $out  = $d->render( eval { JSON::PP->new->decode($j) } // {} );
    return fail("renders: $src") || diag( $d->gap // do { local ( @ARGV, $/ ) = "$dir/err"; <> } ) unless defined $out;
    is run_perl($out), run_perl($src), "round trips: $src" or diag $out;
}

# Q1: a stringify that stores into its `my` target
round_trips($_) for
    'my $s = "a"; $s = "$s$s"; print "$s\n";',
    'my $s = "a"; my $t; $t = "$s$s"; print "$t\n";',
    'my $s = "a"; my $t = "x"; $t = "$t$s"; print "$t\n";',
    'my $n = 1; $n = 2 + $n; $n = "$n$n"; print "$n\n";',
    'sub w { my ($s) = @_; $s = "<" . $s; $s = "$s$s"; $s } print w("a"), "\n";',
    'my $s = "a"; for (1..3) { $s = "$s$s" } print "$s\n";',
    'my $s = "a"; my $r = \$s; $s = "$s$s"; print "$$r\n";';

# Q8: a `local` no handler saves and restores
my $local = qr/GAP: `local` on .* is not yet lowered -- no handler saves and restores it/;
like stderr_of($_), $local, "refused: $_" for
    'our $x = 1; { no strict "refs"; local ${"x"} = 2; } print "$x\n";',
    'our $x = 1; { no strict "refs"; my $n = "x"; local $$n = 2; print $x } print "$x\n";',
    'our @a = (1,2); { no strict "refs"; local @{"a"} = (7); print "@a;" } print "@a\n";',
    'our $x = 1; { no strict "refs"; local *{"x"}; $x = 5 } print "$x\n";',
    'our ($x, $y) = (1, 2); { no strict "refs"; for my $n ("x", "y") { local ${$n} = 9; print "$x$y;" } } print "$x$y\n";';

# what the handlers read stays lowered
unlike stderr_of($_), qr/GAP/, "not refused: $_" for
    'our $g = 1; sub t { local $g = 5; $g } print t(), $g, "\n";',
    'our @g = (1); sub t { local @g = (5); "@g" } print t(), "@g\n";',
    'our %h = (a=>1); sub t { local $h{a} = 5; $h{a} } print t(), $h{a}, "\n";',
    'our $v = 1; sub t { local *v; $v = 2; $v } print t(), $v, "\n";',
    'my $s = "a"; my $t = "$s$s"; print "$t\n";',
    'my $x = 1; $x = $x + 1; print "$x\n";';

done_testing;
