# ABOUTME: Code under `use warnings FATAL` dies where perl would only warn; the graph
# ABOUTME: has no place for that die, so such code is refused by name.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

# THE DEFECT (audit 2026-11-19, probe fl14 -- one of the three whose wire was
# byte-identical to a right program's):
#
#     my $n = "abc";
#     { use warnings FATAL => "all"; my $r = eval { $n + 1 };
#       print defined $r ? "num" : "died", "\n"; }           perl: died
#
# `$n + 1` is an Add on the wire whether or not a warning about "abc" would
# kill it; the lexical warning bits are on the statement's COP and reach no
# node. A consumer made the Add and printed `num`. Every op that can warn is
# a fault under FATAL, which is a control edge this wire does not have: the
# sub (or the program) that holds such a statement is a GAP.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub translate ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return scalar qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>&1 >/dev/null);
}

my $gap = qr/GAP: code under `use warnings FATAL` is not yet lowered/;

like translate('my $n = "abc"; { use warnings FATAL => "all"; my $r = eval { $n + 1 }; print defined $r ? "num" : "died", "\n"; }'),
    $gap, 'FATAL => all, in a block';
like translate('use warnings FATAL => qw(numeric); my $n = "abc"; my $r = eval { $n + 1 }; print defined $r ? "num" : "died", "\n";'),
    $gap, 'one FATAL category, file-wide';
like translate('sub f { use warnings FATAL => "uninitialized"; my $x; return "a" . $x } print eval { f() } // "died", "\n";'),
    qr/skipped main::f: GAP: code under `use warnings FATAL`/, 'in a sub: that sub is refused';

unlike translate('use warnings; my $n = "3"; print $n + 1, "\n";'), qr/GAP/, 'plain warnings lower';
unlike translate('no warnings; my $n = "3"; print $n + 1, "\n";'),  qr/GAP/, 'no warnings lowers';
unlike translate('use warnings FATAL => "all"; no warnings FATAL => "all"; use warnings; my $n = "3"; print $n + 1, "\n";'),
    qr/GAP/, 'FATAL switched off again lowers';

done_testing;
