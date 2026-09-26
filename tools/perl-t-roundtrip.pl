#!/usr/bin/perl
# ABOUTME: Round-trip census over perl's own t/ files -- translate, render,
# ABOUTME: run both, compare STDOUT against what stock perl prints.
#
# THE ORACLE IS THE FILE ITSELF. A t/ file is a TAP producer, so running it
# under stock perl gives the expected output directly -- no recorded block to
# drift, and no question about whether the expectation was verified.
#
# WHY A SEPARATE CENSUS FROM THE PRODUCER ONE. `98/548 files` (2026-08-30) is a
# PRODUCER count: the file translated without a GAP. That says nothing about
# whether the emission runs, and this project's whole lesson is that the two
# diverge -- an emission can translate, render, compile and still print the
# wrong thing. This asks the round-trip question.
#
# MUST RUN FROM THE t/ DIRECTORY. The files `require './test.pl'` and chdir
# themselves; run elsewhere they die on the require and every result is a
# phantom crash. Checked below rather than assumed.
#
#   perl tools/perl-t-roundtrip.pl base comp cmd
#   perl tools/perl-t-roundtrip.pl -v base
use strict;
use warnings;
use JSON::PP;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use SoN::Deparse;

my $LIB  = "$FindBin::Bin/../lib";
my $PERL = $ENV{SON_PERL_T} // "$ENV{HOME}/dev/perl5/t";
die "no perl t/ at $PERL (set SON_PERL_T)\n" unless -d $PERL;

my $verbose = (@ARGV && $ARGV[0] eq '-v') ? shift @ARGV : 0;
my @tiers = @ARGV ? @ARGV : qw(base comp cmd);

my $dir = tempdir( CLEANUP => 1 );
my %tally;
my @differs;
my $n = 0;

for my $tier (@tiers) {
    for my $f (sort glob "$PERL/$tier/*.t") {
        $n++;
        my $rel = "$tier/" . ( $f =~ m{([^/]+)$} )[0];

        # Stock perl, run from t/ so its require and chdir work.
        my $want = qx(cd $PERL && $^X $rel 2>/dev/null </dev/null);
        my $wrc  = $?;

        my $json = qx(cd $PERL && $^X -I$LIB -MO=SoN,json,not_package=SoN $rel 2>$dir/e);
        my $data = eval { JSON::PP->new->decode($json) };
        unless ( $data && $data->{methods} && $data->{methods}{'main::__PROGRAM__'} ) {
            my $e = do { open my $h, '<', "$dir/e"; local $/; <$h> } // '';
            $tally{ $e =~ /GAP:/ ? 'GAP' : 'NOJSON' }++;
            push @differs, [ $rel, 'no graph', '', $want ] if $verbose;
            next;
        }

        # LOADED AT THE TOP, not require'd here. `-I$LIB` is passed to the
        # CHILD processes; this script needs its own `use lib`, and a require
        # that fails inside eval is indistinguishable from an honest refusal.
        # Measured: it reported 9 of 9 REFUSED for t/base, every one of which
        # renders -- a uniform result is a harness bug until proven otherwise.
        my $dp  = SoN::Deparse->new;
        my $out = eval { $dp->render($data) };
        unless ( defined $out ) {
            $tally{REFUSED}++;
            push @differs, [ $rel, '', 'REFUSED: ' . ( $dp->gap // $@ // '?' ),
                $want ] if $verbose;
            next;
        }

        my $g = "$dir/g.pl";
        open my $o, '>', $g or die $!;
        print $o $out;
        close $o;

        # -c FIRST, so a non-compiling emission is its own bucket rather than
        # hiding among the wrong answers as empty output.
        my $chk = qx($^X -I$LIB -c $g 2>&1);
        unless ( $chk =~ /syntax OK/ ) {
            $tally{EMITS_INVALID_PERL}++;
            push @differs, [ $rel, $out, "COMPILE: $chk", $want ] if $verbose;
            next;
        }

        my $got = qx(cd $PERL && $^X $g 2>/dev/null </dev/null);
        if ( $got eq $want ) { $tally{ROUNDTRIP}++ }
        else {
            $tally{DIFFERS}++;
            push @differs, [ $rel, $out, $got, $want ] if $verbose;
        }
    }
}

printf "files: %d\n", $n;
printf "%-20s %d\n", $_, $tally{$_} for sort keys %tally;

for my $d (@differs) {
    printf "\n=== %s ===\n--- emitted ---\n%s--- got ---\n%s--- want ---\n%s",
        $d->@*;
}
