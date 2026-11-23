# ABOUTME: `state $n;` (no initialiser) in a sub or a loop keeps its value between runs, which the
# ABOUTME: walk lowered as a `my`: refused by name; in the program's straight line it is a `my`.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub warnings_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return scalar qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>&1 >/dev/null);
}

# RE-AUDIT 2026-11-23, class D (probes/r o24, q01, q02): only `state $x = V`
# (the `once` op) was handled; `sub c { state $n; $n .= "x"; $n } c(); print
# c()` printed x for perl's xx.
my $GAP = qr/GAP: a `state` variable with no initialiser, where it can be reached more than once/;
my %refused = (
    'a scalar in a sub'   => 'use feature "state"; sub c { state $n; $n.="x"; $n } c(); print c(),"\n";',
    'an array in a sub'   => 'use feature "state"; sub c { state @l; push @l,1; scalar @l } c(); print c(),"\n";',
    'a hash in a sub'     => 'use feature "state"; sub c { state %h; $h{$_[0]}++; scalar keys %h } c("a"); print c("b"),"\n";',
    'in an anon sub'      => 'use feature "state"; my $f = sub { state $n; $n++; $n }; $f->(); print $f->(), "\n";',
    'in a program loop'   => 'use feature "state"; for my $i (1,2) { state $n; $n++; print $n } print "\n";',
);
like warnings_of($refused{$_}), $GAP, "refused: $_" for sort keys %refused;

unlike warnings_of('use feature "state"; state $n; $n++; print "$n\n";'),
    qr/GAP:/, 'in the program\'s straight line it runs once, as a `my` does';

done_testing;
