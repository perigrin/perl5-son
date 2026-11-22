# ABOUTME: SoN::Verify over the corpus, the probes and chalk's lib: no rule broken but by the
# ABOUTME: violations held by name; no fewer wires or graphs than t/data/wire-verify-baseline.tsv.
use v5.42.0;
use Test2::V0;
$ENV{PERL_HASH_SEED}    = 0;
$ENV{PERL_PERTURB_KEYS} = 0;

# WHAT THIS HOLDS. tools/wire-verify.pl runs the wire verifier over the pvm
# corpus, the audit's probes and (opt-in) chalk's lib. EVERY RULE IS HARD
# (wire v2 stage 10): a violation of any rule fails, but those %HELD names,
# each with why it is not fixed. Until stage 10 this was a ratchet -- each
# rule's count per source might fall, not rise (t/data/wire-verify-baseline.tsv),
# and chalk's lib per graph, a graph not recorded printed and not failed;
# every count is 0 now but the held, so the counts are gone: a different
# violation could have taken a held one's place under a count.
#
# THE DENOMINATOR IS HELD. A violation also vanishes when wires stop being
# produced, so `#wires` and `#graphs` may not drop below the baseline's: a sub
# the producer starts to refuse leaves its wire standing and takes its
# violations with it. (An arm-scan change refused 15 of chalk's graphs and
# four rows "fell"; only this number said why.) A change that removes graphs
# on purpose lowers the row with its reason.
#
# A DROPPED WIRE FAILS, in every source: a compile that failed or ran out of
# time used to take its violations out of every row in silence.
#
# ONE HASH ORDER: every wire is compiled under PERL_HASH_SEED=0.
#
# RUNS BY DEFAULT (about three minutes: 975 compiles). An opt-in guard is the
# kind nobody runs. chalk's lib is opt-in -- SON_RATCHET=1, with SON_CHALK or
# ~/dev/chalk -- because it is another repository's working tree and takes
# half an hour.
# SON_WIRE_CACHE=DIR reuses wires (see the tool: a stale cache lies).
# SON_WIRE_JOBS=N compiles N wires at a time.

# A VIOLATION HELD, by source, case and graph, and rule: why it is not fixed.
# One that no longer occurs is printed: take it out.
my %HELD = (
    'probes p/pl13:main::sw record' =>
        'a list assignment to package scalars that is its sub\'s value: its EntryWrites store, and the Assign '
      . 'is the value, on neither chain; what node that value is wants a design (chalk T2 refuses it by name)',
    # (perl's own DynaLoader, which chalk's runtime module follows, was held
    # here as "not traced yet": traced, its subs were compiled with the
    # peephole on, and B::SoN now refuses their aelemfast by name --
    # t/wire-a-fused-element-op-is-refused.t)
);

my $baseline = 't/data/wire-verify-baseline.tsv';
my %want;
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
    diag "chalk's lib checked at $at";
    push @args, '--chalk', $chalk;
}
else { note 'chalk lib not checked: SON_RATCHET=1 (and SON_CHALK) runs it' }
push @args, '--wires', $ENV{SON_WIRE_CACHE} if $ENV{SON_WIRE_CACHE};
push @args, '--jobs',  $ENV{SON_WIRE_JOBS}  if $ENV{SON_WIRE_JOBS};

# The v2 rules of docs/plans/2026-11-20-wire-v2.md, section 8.
my ( %got, @hard, %held );
for ( split /\n/, qx($^X tools/wire-verify.pl --tsv @args) ) {
    my ( $source, $rule, @rest ) = split /\t/;
    if ( $rule eq '!' ) {    # a violation: SOURCE ! CASE:GRAPH#NODE OP RULE DETAIL
        my ( $where, $op, $r, $detail ) = @rest;
        my $k = "$source " . ( $where =~ s/#\d+\z//r ) . " $r";
        if ( $HELD{$k} ) { $held{$k} = 1; next }
        push @hard, "$source $where $op $r: $detail";
        next;
    }
    $got{$source}{$rule} = $rest[0];
}

for my $source ( sort keys %got ) {
    subtest $source => sub {
        my $g = $got{$source};
        is $g->{'#dropped'} // 0, 0, 'no wire dropped (a failed or timed-out compile)';
        return if $source eq 'chalk';    # (its lib changes with every chalk stage)
        ok exists $want{$source}, 'the baseline has this source' or return;
        cmp_ok $g->{'#wires'},  '>=', $want{$source}{'#wires'},  'no fewer wires than the baseline';
        cmp_ok $g->{'#graphs'}, '>=', $want{$source}{'#graphs'}, 'no fewer graphs than the baseline';
    };
}
ok scalar( grep { $got{$_} } qw(corpus probes) ) == 2, 'corpus and probes were measured';
is \@hard, [], 'no violation of any rule (but those %HELD names)';
diag "held by name: $_" for sort keys %held;
diag "held, and no longer seen (take it out of %HELD): $_" for grep { !$held{$_} && ( /\Achalk / ? $got{chalk} : 1 ) } sort keys %HELD;

done_testing;
