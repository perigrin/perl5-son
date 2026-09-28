# ABOUTME: The goal's two round-trip numbers, guarded -- a regression fails here
# ABOUTME: rather than waiting for someone to remember to run a census by hand.
use v5.42.0;
use Test2::V0;
use FindBin;

# THE GOAL'S NUMBERS WERE GUARDED BY NOTHING. Both censuses are scripts in
# tools/ that no test invoked, so 154/213 and 12/39 held only as long as someone
# remembered to run them -- and every claim about them in docs/plans came from a
# manual run. A regression would have passed the whole suite.
#
# Found by pvm reporting the identical defect on their side: their 620-file goal
# moved 185 -> 278 while all six of their ratchets stayed byte-identical,
# because `parse.Parse(src []byte)` takes no loader and every baseline was blind
# to the resolution the goal depends on. That is the fifth instrument this
# session measuring something adjacent to its question; this file closes mine.
#
# A RATCHET, NOT AN EXACT MATCH. The corpus is pvm's and grows -- 210 -> 213
# output blocks in one afternoon -- so pinning an exact count would fail on
# their next commit and teach the reader to ignore it. It fails on a DROP.
#
# OPT-IN, because the corpus census takes ~3 minutes: too slow to pay on every
# `prove` run, and skipping silently would make this another unchecked
# instrument. `SON_RATCHET=1 prove -Ilib t/roundtrip-ratchet.t` runs it, and the
# skip message says so.

my %FLOOR = (
    # Raise these when a fix moves them. Lowering one needs a reason in the
    # commit message -- a floor that follows the number down guards nothing.
    #
    # BOTH MEASURED, not recalled. `perl_t` stood at 12 from the day this file
    # was written and the census has never reported more than 11 -- so the
    # ratchet FAILED on every run, which is to say it was never run. An opt-in
    # guard nobody runs is the decorative kind; a floor above the real number is
    # how it got that way.
    corpus => 170,   # 4d30e51, measured on pvm e87dee9c (224 cases)
    perl_t => 11,    # base/lex.t refuses on a `caller` bound to a list
);

# ONE RUN PER TOOL. The corpus census takes ~3 minutes, and a first draft of
# this file called it from three subtests -- nine minutes to check three facts
# about one measurement, which is the kind of cost that gets a ratchet disabled.
my %CENSUS;
sub census ($tool, @args) {
    return $CENSUS{$tool}->@* if $CENSUS{$tool};
    my $out = qx($^X $FindBin::Bin/../tools/$tool @args 2>&1);
    my %n;
    $n{$1} = $2 while $out =~ /^(\w+)\s+(\d+)$/mg;
    $n{_cases} = $1 if $out =~ /^(?:cases|files):\s*(\d+)$/m;
    $CENSUS{$tool} = [ \%n, $out ];
    return ( \%n, $out );
}

SKIP: {
    skip_all 'set SON_RATCHET=1 to run the round-trip censuses (~4 minutes)'
        unless $ENV{SON_RATCHET};

    subtest 'the corpus round-trip does not regress' => sub {
        my ( $n, $out ) = census('corpus-roundtrip.pl');

        # THE DENOMINATOR IS CHECKED FIRST. A census that parsed nothing reports
        # 0 of everything and would pass a floor test by vacuous truth -- the
        # harness bug this project has hit three times.
        ok( ( $n->{_cases} // 0 ) > 200,
            "the census found its cases ($n->{_cases})" )
            or do { diag $out; return };

        my $sum = ( $n->{ROUNDTRIP} // 0 ) + ( $n->{DIFFERS} // 0 )
                + ( $n->{REFUSED}   // 0 ) + ( $n->{NOJSON}  // 0 );
        is $sum, $n->{_cases}, 'every case landed in exactly one bucket'
            or diag $out;

        ok( ( $n->{ROUNDTRIP} // 0 ) >= $FLOOR{corpus},
            "ROUNDTRIP $n->{ROUNDTRIP} >= floor $FLOOR{corpus}" )
            or diag $out;
    };

    subtest 'the perl t/ round-trip does not regress' => sub {
        my ( $n, $out ) = census('perl-t-roundtrip.pl');

        ok( ( $n->{_cases} // 0 ) >= 39,
            "the census found its files ($n->{_cases})" )
            or do { diag $out; return };

        ok( ( $n->{ROUNDTRIP} // 0 ) >= $FLOOR{perl_t},
            "ROUNDTRIP $n->{ROUNDTRIP} >= floor $FLOOR{perl_t}" )
            or diag $out;
    };

    # EVERY EMISSION MUST COMPILE. This is the floor worth guarding separately
    # from the percentage: a wrong answer can be investigated, an emission perl
    # refuses cannot be run by anything downstream. It went 5 -> 0 this session.
    subtest 'no corpus emission fails to compile' => sub {
        my ( $n, $out ) = census('corpus-roundtrip.pl');

        # THE TALLY MUST BE THERE. Until d455b7f the census never printed it,
        # and `// 0` passed this on every corpus -- a zero read from nothing.
        ok defined $n->{EMITS_INVALID_PERL}, 'the census counted it'
            or do { diag $out; return };
        is $n->{EMITS_INVALID_PERL}, 0,
            'EMITS_INVALID_PERL is zero' or diag $out;
    };
}

done_testing;
