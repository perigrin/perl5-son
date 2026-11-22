# ABOUTME: Translating a nest of loops takes time linear in its depth (wire v2 stage 9b): a
# ABOUTME: depth-14 nest translates in under two seconds (it took about 20 s with the scouts).
use v5.42.0;
use Test2::V0;
use Time::HiRes qw(time);
use SoN::FromOptree;

# WHY: docs/plans/2026-11-20-wire-v2.md, 5.1 -- each scout walked the body and
# the body's inner loops scouted again, so the time doubled per nesting level
# (audit 2.2: depth 14, 20 s). Braun walks each body once.

my $depth = 14;
my $src = 'sub { my $s = 0; '
        . join( '', map { "for my \$v$_ (1..2) { " } 1 .. $depth )
        . '$s += $v1 + $v' . $depth . '; '
        . ( '} ' x $depth ) . '$s }';
my $cv = eval $src or die $@;
my $t0 = time;
my $g = SoN::FromOptree->translate($cv);
my $took = time - $t0;
ok $g, "a depth-$depth nest translates";
cmp_ok $took, '<', 2, "in under 2 s (took ${\ sprintf '%.2f', $took} s)";

done_testing;
