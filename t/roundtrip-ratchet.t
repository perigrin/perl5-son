# ABOUTME: The goal's round-trip numbers -- pvm corpus, perl's t/, chalk's lib/ and chalk's
# ABOUTME: own test suite against it -- guarded, so a regression fails here, not by hand.
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
    corpus => 279,   # t/corpus/mdtest/pvm (pvm 50cd3b10 + 21 local), measured twice 2026-10-11
    perl_t => 11,    # base/lex.t refuses on a `caller` bound to a list
    # chalk's lib/ at the commit tools/chalk-lib-roundtrip.pl pins (5948f648,
    # 179 modules), measured at d0cb68a and 2d8fb90, 2026-10-06.
    chalk_compiles => 137,
    # chalk's own test files (547 at 5948f648) that give the SAME result
    # against the emitted lib/ -- tools/chalk-gate3.pl. The 59 that read lib/
    # as source are DEFERRED to chalk's own lowering (perigrin, 2026-10-09),
    # so 488 are measured; files that time out against the ORIGINAL are SLOW
    # and left out. Measured 488 of 488 at eddfaa3, twice, 2026-10-09.
    chalk_gate3_matching => 488,
);

# A CEILING, NOT A FLOOR: graphs B::SoN skipped in chalk's lib/. A module can
# compile with some of its graphs skipped, so COMPILES alone could hold while
# the parse gate slipped. Lowering this needs no reason; raising it does.
my %CEILING = (
    # Measured 226 at d25e6c2, twice, 2026-10-11 (229 at 1c8634e; 239 at
    # d0cb68a and 2d8fb90).
    chalk_skipped_graphs => 226,
    # perl t/ emissions perl will not compile. Unguarded until 75d3db8, so
    # two new ones (comp/fold.t, comp/retainedlines.t) arrived unnoticed.
    # Measured 1 at 1c8634e, twice, 2026-10-11: comp/line_debug.t (a
    # symbolic `@{"_<..."}` the producer drops). comp/parser_run.t now
    # compiles; it differs instead.
    perl_t_invalid => 1,
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
    skip_all 'set SON_RATCHET=1 to run the round-trip censuses (~1.5 hours)'
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
        ok defined $n->{EMITS_INVALID_PERL}, 'the census counted invalid emissions'
            or diag $out;
        ok( ( $n->{EMITS_INVALID_PERL} // 9e9 ) <= $CEILING{perl_t_invalid},
            "EMITS_INVALID_PERL $n->{EMITS_INVALID_PERL} <= ceiling $CEILING{perl_t_invalid}" )
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

    # CHALK'S lib/, one module at a time. The census reads a pinned commit from
    # a chalk clone (SON_CHALK, or ~/dev/chalk) -- never the working tree -- so
    # chalk's own progress cannot move these numbers.
    subtest "chalk's lib/ round-trip does not regress" => sub {
        my ( $n, $out ) = census('chalk-lib-roundtrip.pl');

        is $n->{_cases}, 179, 'the census found every module at the pinned commit'
            or do { diag $out; return };

        my $sum = 0;
        $sum += $n->{$_} // 0 for qw(COMPILES COMPILES_PARTIAL INVALID REFUSED NOJSON);
        is $sum, $n->{_cases}, 'every module landed in exactly one bucket'
            or diag $out;

        ok( ( $n->{COMPILES} // 0 ) >= $FLOOR{chalk_compiles},
            "COMPILES $n->{COMPILES} >= floor $FLOOR{chalk_compiles}" )
            or diag $out;
        ok defined $n->{INVALID}, 'the census counted INVALID' or diag $out;
        is $n->{INVALID}, 0, 'no module emits Perl that does not compile'
            or diag $out;
        ok defined $n->{SKIPPED_GRAPHS}, 'the census counted skipped graphs'
            or diag $out;
        ok( ( $n->{SKIPPED_GRAPHS} // 9e9 ) <= $CEILING{chalk_skipped_graphs},
            "SKIPPED_GRAPHS $n->{SKIPPED_GRAPHS} <= ceiling $CEILING{chalk_skipped_graphs}" )
            or diag $out;
    };

    # CHALK'S OWN TEST SUITE against the emitted lib/ -- the goal's last gate.
    # Every module that round-trips with no graph skipped replaces its
    # original, and each test file must give the same result. The slowest
    # census by far: chalk's suite runs twice.
    subtest "chalk's test suite against the emitted lib/ does not regress" => sub {
        my ( $n, $out ) = census('chalk-gate3.pl');

        is $n->{_cases}, 547, 'the census ran every test file at the pinned commit'
            or do { diag $out; return };

        my $sum = 0;
        $sum += $n->{$_} // 0 for qw(SAME DIFFERS SLOW DEFERRED);
        is $sum, $n->{_cases}, 'every test file landed in exactly one bucket'
            or diag $out;

        # THE DEFERRED SET IS A FACT OF THE PINNED COMMIT: the tests that read
        # lib/ as source. A change in the classifier would move files in or
        # out of the measured set silently; this makes it loud.
        is $n->{DEFERRED}, 59, 'the 59 tests that read lib/ as source are deferred'
            or diag $out;

        my $matching = $n->{SAME} // 0;
        ok( $matching >= $FLOOR{chalk_gate3_matching},
            "SAME $matching >= floor $FLOOR{chalk_gate3_matching}" )
            or diag $out;
    };
}

done_testing;
