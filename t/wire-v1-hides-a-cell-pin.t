# ABOUTME: Wire v1 writes a program with cells as the commit before wire v2 did, byte for byte,
# ABOUTME: though wire v2 now places each MakeCell on the control chain (closures in a row).
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use Cwd qw(getcwd);

# The pinned MakeCell is hidden from v1 by its writer (SoN::Serialize::JSON
# _on_chain, _v1_after_cell); v1's node order is a walk over consumer lists,
# so the cells must be met where v1 met them. Three cells made one after the
# other (chalk's Graph::nodes: three named subs a closure calls) moved ids
# until the walk went through a chain of cells. The full proof is
# t/wire-v2-downgrades-to-v1.t over chalk's lib; this is its fast part.
my $BASE = '315dd0391047b73ea7929a5b40eee9c0525a0c73';
my $root = getcwd();
$ENV{PERL_HASH_SEED} = 0;
$ENV{PERL_PERTURB_KEYS} = 0;
my $base = $ENV{SON_V1_BASE};
unless ( $base && -d "$base/lib" ) {
    $base = tempdir( CLEANUP => 1 );
    system("git -C '$root' archive $BASE 2>/dev/null | tar -x -C '$base'") == 0 && -d "$base/lib"
        or skip_all "no checkout of $BASE: set SON_V1_BASE";
}
my $dir = tempdir( CLEANUP => 1 );
my @src = (
    q{use v5.40; use Scalar::Util qw(blessed); sub g ($x) { my @s = ($x); my $v = sub ($n) { return false unless blessed($n); true }; while (@s) { my $n = pop @s; next unless $v->($n) } return 1 } print g(3), "\n";},
    q{my ($a, $b, $c) = (1, 2, 3); my $f = sub { $a + $b + $c }; for my $i (1 .. 2) { $a += $i } print $f->(), "\n";},
    q{my $x = 1; my $g = sub { $x }; my $y = 2; my $h = sub { $y + $x }; if ($x) { $y++ } print $g->(), $h->(), "\n";},
);
for my $i ( 0 .. $#src ) {
    open my $o, '>', "$dir/c$i.pl" or die $!;
    print $o $src[$i];
    close $o;
    for my $t ( [ $base, 'old' ], [ $root, 'new' ] ) {
        system("mkdir -p $dir/$t->[1]/c && $^X -I$t->[0]/lib -MO=-q,SoN,json,not_package=SoN $dir/c$i.pl > $dir/$t->[1]/c/c$i.json 2>/dev/null");
    }
}
my $diff = qx($^X tools/wire-diff.pl $dir/old $dir/new 2>&1);
like $diff, qr/^# 0 of 3 wires differ$/m, 'v1 is the base wire for cells in a row' or diag $diff;

done_testing;
