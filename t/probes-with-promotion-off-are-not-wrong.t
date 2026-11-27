# ABOUTME: The promotion differential: chalk's audit probes with SON_NO_PROMOTE=1 print nothing perl
# ABOUTME: does not (WRONG 0, TIMEOUT 0), as they must with promotion on. Opt-in; tools/gates.sh runs it.
use v5.42.0;
use Test2::V0;
use Cwd qw(abs_path);

# WHY (audit 4, X5). SoN::Promote's proof called a captured `my` private, and
# V14, asking the same proof, agreed: 16 probes printed a wrong answer that
# SON_NO_PROMOTE=1 did not. The probes gate runs with promotion on only, so
# a wrong answer that comes from construction and one that comes from the
# pass look alike, and one that promotion hides is not seen at all. This
# sweeps the same probe set with the pass off; the gate holds both runs to
# WRONG 0, so neither mode may print what the other does not get right.
#
# OPT-IN: SON_PROMOTE_DIFF=1, with SON_CHALK (else ~/dev/chalk). About as long
# as the probes gate. SON_PROBE_JOBS=N (2). tools/gates.sh's probes phase
# runs it on its snapshots.
skip_all 'SON_PROMOTE_DIFF=1 runs the probe sweep with promotion off' unless $ENV{SON_PROMOTE_DIFF};
my $chalk = $ENV{SON_CHALK} // "$ENV{HOME}/dev/chalk";
skip_all "no chalk at $chalk (SON_CHALK)" unless -f "$chalk/tools/audit-probes.pl";

my $lib  = abs_path('lib');
my $jobs = $ENV{SON_PROBE_JOBS} // 2;
my $out  = do {
    local $ENV{SON_NO_PROMOTE} = 1;
    local $ENV{PERL5_SON_LIB}  = $lib;
    qx(cd '$chalk' && $^X -Ilib -It/lib tools/audit-probes.pl --jobs $jobs 2>&1);
};
my ($counts) = $out =~ /^([A-Z]+=\d+(?: [A-Z]+=\d+)*)$/m;
ok( $counts, 'the sweep printed its counts' ) or diag substr( $out, -2000 );
my %n = map { split /=/ } split ' ', $counts // '';
note "promotion off: $counts" if $counts;
my @bad = grep { /^\S+\s+(?:WRONG|TIMEOUT)\b/ } split /\n/, $out;
is( $n{WRONG}   // 0, 0, 'promotion off: no probe prints what perl does not' ) or diag join "\n", grep { /WRONG/ } @bad;
is( $n{TIMEOUT} // 0, 0, 'promotion off: no probe times out' ) or diag join "\n", grep { /TIMEOUT/ } @bad;
done_testing;
