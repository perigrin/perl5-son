# ABOUTME: The LLVM corpus census asks B::SoN for the wire version SON_WIRE names, so the
# ABOUTME: gates can run on wire 2 (wire v2 stage 5); unset, B::SoN's default.

use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use FindBin;

my $chalk = $ENV{SON_CHALK} // "$ENV{HOME}/dev/chalk";
skip_all "no chalk clone at $chalk (set SON_CHALK)" unless -d "$chalk/.git";
skip_all 'no lli on PATH' unless grep { -x "$_/lli" } split /:/, $ENV{PATH};

my $dir = tempdir(CLEANUP => 1);
open my $fh, '>', "$dir/cases.md" or die $!;
print $fh <<'MD';
## adds

```perl
my $x = 1 + 2; print "x=$x\n";
```

```output
x=3
```
MD
close $fh;

# census($wire) -> its tally lines, SON_WIRE set to $wire (undef: unset)
sub census ($wire) {
    local $ENV{SON_CORPUS} = $dir;
    local $ENV{SON_WIRE} = $wire;
    delete $ENV{SON_WIRE} unless defined $wire;
    return scalar qx($^X $FindBin::Bin/../tools/corpus-llvm-roundtrip.pl --commit HEAD --jobs 1 2>&1);
}

like( census(undef), qr/^ROUNDTRIP\s+1$/m, 'unset: the default wire round-trips' );
like( census(2),     qr/^ROUNDTRIP\s+1$/m, 'SON_WIRE=2: round-trips' );
# (a wire B::SoN does not write gives no graph: it was asked for)
like( census(7),     qr/^NOJSON\s+1$/m,    'SON_WIRE=7: B::SoN was asked for wire 7' );
done_testing;
