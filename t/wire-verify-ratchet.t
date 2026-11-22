# ABOUTME: The ratchet on SoN::Verify's counts: no memory-chain rule may be broken
# ABOUTME: more often than t/data/wire-verify-baseline.tsv records. Counts may fall.
use v5.42.0;
use Test2::V0;
use lib 'tools/lib';
use WireRatchet qw(parse_graph_lines compare_graphs);

$ENV{PERL_HASH_SEED}    = 0;
$ENV{PERL_PERTURB_KEYS} = 0;

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
# produced, so `#wires` may not drop below the baseline's -- nor `#graphs`: a
# sub the producer starts to refuse leaves its wire standing and takes its
# violations out of every row. (An arm-scan change refused 15 of chalk's
# graphs and four rows "fell"; only this number said why.) A change that
# removes graphs on purpose lowers the row with its reason.
#
# CHALK'S LIB IS HELD PER GRAPH (perigrin, 2026-11-21). Its lib changes in
# every chalk-side stage, so its totals moved with graphs the producer never
# saw before. t/data/wire-verify-chalk-graphs.tsv records each graph's count
# per rule (the most one wire counts): a recorded graph may not rise; a graph
# not in the record is printed, not failed; chalk's totals are printed, not
# held. Re-record it (tools/wire-verify.pl --tsv --chalk ..., its `@` lines)
# when a chalk branch merges.
#
# A DROPPED WIRE FAILS, in every source: a compile that failed or ran out of
# time used to take its violations out of every row in silence.
#
# ONE HASH ORDER. The producer is not deterministic on every input (chalk's
# Target/LLVM/Lower.pm has two graph shapes run to run), so every wire is
# compiled under PERL_HASH_SEED=0.
#
# RUNS BY DEFAULT (about three minutes: 870 compiles). An opt-in guard is the
# kind nobody runs. chalk's lib is opt-in -- SON_RATCHET=1, with SON_CHALK or
# ~/dev/chalk -- because it is another repository's working tree and takes
# half an hour.
# V6 (read-unversioned:*) IS HARD (wire v2 stage 7): zero in every source,
# chalk's lib included; the baseline has no row for it.
# SON_WIRE_CACHE=DIR reuses wires (see the tool: a stale cache lies).
# SON_WIRE_JOBS=N compiles N wires at a time.

my $baseline = 't/data/wire-verify-baseline.tsv';
my $graphs   = 't/data/wire-verify-chalk-graphs.tsv';
my %want;
my ($chalk_at) = do { open my $g, '<', $graphs or die "$graphs: $!"; map {/^# chalk at (\w+)/} <$g> };
open my $fh, '<', $baseline or die "$baseline: $!";
while (<$fh>) {
    chomp;
    next if /^#/ || !length;
    my ( $source, $rule, $n ) = split /\t/;
    $want{$source}{$rule} = $n;
}
close $fh;

my @args  = ( '--corpus', '--probes' );
my $chalk = $ENV{SON_CHALK} // "$ENV{HOME}/dev/chalk";
if ( $ENV{SON_RATCHET} && -d "$chalk/lib" ) {
    # SON_CHALK_AT names the commit of a copy that is not a checkout
    # (tools/gates.sh runs this on snapshots).
    chomp( my $at = $ENV{SON_CHALK_AT} // `git -C '$chalk' rev-parse --short=8 HEAD 2>/dev/null` );
    diag "chalk's lib counted at $at, per graph (recorded at " . ( $chalk_at // '?' ) . ')';
    push @args, '--chalk', $chalk;
}
else { note 'chalk lib not checked: SON_RATCHET=1 (and SON_CHALK) runs it' }
push @args, '--wires', $ENV{SON_WIRE_CACHE} if $ENV{SON_WIRE_CACHE};
push @args, '--jobs',  $ENV{SON_WIRE_JOBS}  if $ENV{SON_WIRE_JOBS};

# The v2 rules of docs/plans/2026-11-20-wire-v2.md, section 8 (the one wire).
my ( %got, @graph_lines );
for ( split /\n/, qx($^X tools/wire-verify.pl --tsv @args) ) {
    if (/^\w+\t@/) { push @graph_lines, $_; next }
    my ( $source, $rule, $n ) = split /\t/;
    $got{$source}{$rule} = $n;
}

for my $source ( sort keys %got ) {
    subtest $source => sub {
        my $g = $got{$source};
        is $g->{'#dropped'} // 0, 0, 'no wire dropped (a failed or timed-out compile)';
        # EVERY READ NAMES A VERSION (V6), in every source and every graph:
        # hard since wire v2 stage 7, not a row.
        is [ map {"$_ $g->{$_}"} grep { /^read-unversioned:/ && $g->{$_} } sort keys %$g ], [],
            'V6: no read without a memory version';
        if ( $source =~ /^chalk/ ) {
            note "$source: $_ $g->{$_}" for sort keys %$g;
            return;
        }
        ok exists $want{$source}, 'the baseline has this source' or return;
        my $w = $want{$source};
        cmp_ok $g->{'#wires'}, '>=', $w->{'#wires'}, 'no fewer wires than the baseline';
        cmp_ok $g->{'#graphs'}, '>=', $w->{'#graphs'}, 'no fewer graphs than the baseline';
        for my $rule ( sort grep { !/^#|^allowed:/ } keys %{ { %$g, %$w } } ) {
            my ( $now, $was ) = ( $g->{$rule} // 0, $w->{$rule} // 0 );
            cmp_ok $now, '<=', $was, "$rule: $now, baseline $was";
            note "$rule fell $was -> $now: lower $baseline" if $now < $was;
        }
    };
}
ok scalar( grep { $got{$_} } qw(corpus probes) ) == 2, 'corpus and probes were measured';

if ( my @chalk = grep {/^chalk/} sort keys %got ) {
    my $file = $graphs;
    open my $gf, '<', $file or die "$file: $!";
    my $record = parse_graph_lines(<$gf>);
    my $now    = parse_graph_lines(@graph_lines);
    $now->{$_} //= {} for @chalk;
    my $c = compare_graphs( $record, $now );
    subtest "chalk's lib, per graph" => sub {
        ok exists $record->{$_}, "$file records $_" for @chalk;
        is scalar $c->{rose}->@*, 0, 'no recorded graph rose';
        diag "ROSE $_->[0] $_->[1] $_->[2]: $_->[3] -> $_->[4]" for $c->{rose}->@*;
        note "fell $_->[0] $_->[1] $_->[2]: $_->[3] -> $_->[4]" for $c->{fell}->@*;
        my @new = grep { keys $_->[2]->%* } $c->{new}->@*;
        diag sprintf 'new graphs: %d, %d of them with violations (printed, not held)', scalar $c->{new}->@*, scalar @new;
        for my $n (@new) { diag "new $n->[0] $n->[1]: " . join ',', map {"$_=$n->[2]{$_}"} sort keys $n->[2]->%* }
        diag "gone $_->[0] $_->[1]" for $c->{gone}->@*;
    };
}

done_testing;
