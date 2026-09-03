# ABOUTME: The per-iteration capture case -- one MakeCell SITE, three distinct cells.
# ABOUTME: The oracle is 1,2,3 vs 3,3,3, not repetition: both designs are stable per line.
use 5.42.0;

# READ-ONLY per-iteration. A per-SITE cell gives 3,3,3 (last value wins);
# per-EXECUTION gives 1,2,3.
my @subs;
for my $i (1..3) { push @subs, sub { $i } }
print join(",", map { $_->() } @subs), "\n";     # 1,2,3
print join(",", map { $_->() } @subs), "\n";     # 1,2,3  -- stable, so repetition does NOT discriminate

# WRITABLE per-iteration. This one separates the designs twice over: each
# closure must own a SEPARATE mutable cell and increment it independently.
my @w;
for my $j (1..3) { push @w, sub { $j++ } }
print join(",", map { $_->() } @w), "\n";        # 1,2,3
print join(",", map { $_->() } @w), "\n";        # 2,3,4  -- per-site would give 4,4,4
