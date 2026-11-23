# ABOUTME: A `defer` block, and a try's `finally` (perl's pushdefer op), run on every way out of
# ABOUTME: their scope; the walk dropped them: refused by name.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub warnings_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return scalar qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>&1 >/dev/null);
}

# RE-AUDIT 2026-11-23, class C (probes/r b30, d01, d02, q06, r01, r02): no
# handler, so the block was not on the wire and nothing refused it --
# `try { $x=1 } catch ($e) { $x=9 } finally { $x.=3 } print $x` printed 1
# for perl's 13.
my $GAP = qr/GAP: a `defer` or `finally` block is not yet lowered/;
my %refused = (
    'finally'               => 'use feature "try"; no warnings; my $x=0; try { $x=1 } catch ($e) { $x=9 } finally { $x.=3 } print "$x\n";',
    'finally in a sub'      => 'use feature "try"; no warnings; sub f { my $l=""; try { die "x\n" } catch ($e) { $l.="c" } finally { $l.="f" } $l } print f(),"\n";',
    'defer in a bare block' => 'use feature "defer"; no warnings; my $x=1; { defer { $x=2 } $x=3; } print "$x\n";',
    'defer in a sub'        => 'use feature "defer"; no warnings; our $g=1; sub f { defer { $g=2 } return 5 } f(); print "$g\n";',
);
like warnings_of($refused{$_}), $GAP, "refused: $_" for sort keys %refused;

unlike warnings_of('use feature "try"; no warnings; my $x=0; try { $x=1 } catch ($e) { $x=9 } print "$x\n";'),
    qr/GAP:/, 'a try with no finally is not refused';

done_testing;
