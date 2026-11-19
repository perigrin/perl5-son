# ABOUTME: The ratchet on SoN::Verify's counts: no memory-chain rule may be broken
# ABOUTME: more often than t/data/wire-verify-baseline.tsv records. Counts may fall.
use v5.42.0;
use Test2::V0;

# WHAT THIS HOLDS. tools/wire-verify.pl runs the wire verifier over the pvm
# corpus and the audit's probes; the baseline is what it counted on the day
# the verifier was written (2026-11-19). The producer breaks these rules today
# -- that is the audit's finding -- so the baseline is not zero. Each later
# step (pin every store, version every read, the eval catch edge) lowers some
# rows; this test is what stops any row going back up meanwhile.
#
# A FALL IS NOT A FAILURE, but the note it prints is a request: lower the
# baseline in the same commit, or the next rise back to the old number passes.
#
# THE DENOMINATOR IS HELD TOO. A count also falls when wires stop being
# produced, so `#wires` may not drop below the baseline's.
#
# RUNS BY DEFAULT (about three minutes: 870 compiles). An opt-in guard is the
# kind nobody runs. chalk's lib is opt-in -- SON_RATCHET=1, with SON_CHALK or
# ~/dev/chalk at the commit the baseline names -- because it is another
# repository's working tree and takes half an hour.
# SON_WIRE_CACHE=DIR reuses wires (see the tool: a stale cache lies).

my $baseline = 't/data/wire-verify-baseline.tsv';
my ( %want, $chalk_at );
open my $fh, '<', $baseline or die "$baseline: $!";
while (<$fh>) {
    chomp;
    $chalk_at = $1 if /^# chalk at (\w+)/;
    next if /^#/ || !length;
    my ( $source, $rule, $n ) = split /\t/;
    $want{$source}{$rule} = $n;
}
close $fh;

my @args  = ( '--corpus', '--probes' );
my $chalk = $ENV{SON_CHALK} // "$ENV{HOME}/dev/chalk";
if ( $ENV{SON_RATCHET} && -d "$chalk/lib" ) {
    chomp( my $at = `git -C '$chalk' rev-parse --short HEAD 2>/dev/null` );
    if   ( $at eq ( $chalk_at // '' ) ) { push @args, '--chalk', $chalk }
    else                                { note "chalk is at $at, the baseline at $chalk_at: not compared" }
}
else { note 'chalk lib not checked: SON_RATCHET=1 (and SON_CHALK) runs it' }
push @args, '--wires', $ENV{SON_WIRE_CACHE} if $ENV{SON_WIRE_CACHE};

my %got;
for ( split /\n/, qx($^X tools/wire-verify.pl --tsv @args) ) {
    my ( $source, $rule, $n ) = split /\t/;
    $got{$source}{$rule} = $n;
}

for my $source ( sort keys %got ) {
    subtest $source => sub {
        ok exists $want{$source}, 'the baseline has this source' or return;
        my ( $g, $w ) = ( $got{$source}, $want{$source} );
        cmp_ok $g->{'#wires'}, '>=', $w->{'#wires'}, 'no fewer wires than the baseline';
        for my $rule ( sort grep { !/^#|^allowed:/ } keys %{ { %$g, %$w } } ) {
            my ( $now, $was ) = ( $g->{$rule} // 0, $w->{$rule} // 0 );
            cmp_ok $now, '<=', $was, "$rule: $now, baseline $was";
            note "$rule fell $was -> $now: lower $baseline" if $now < $was;
        }
    };
}
ok scalar( grep { $got{$_} } qw(corpus probes) ) == 2, 'corpus and probes were both measured';

done_testing;
