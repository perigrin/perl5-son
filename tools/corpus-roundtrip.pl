#!/usr/bin/perl
# ABOUTME: Round-trip census over pvm's conformance corpus -- translate each
# ABOUTME: perl block, render it back, run both, compare STDOUT against the block.
#
# WHY THIS IS IN THE REPO. It was an ad-hoc script for a week, which is exactly
# the shape that produced three wrong censuses in this project: a harness is a
# program and it fails the same ways the code under test does, silently and with
# a number attached. Committed so the denominator can be checked.
#
# THE DENOMINATOR IS OUTPUT BLOCKS, NOT CASES, and it MOVES -- the corpus is
# pvm's and grows while we measure. A few `parses: no` cases pin no output at
# all, because perl builds no optree for a program it will not compile, so the
# `cases:` line is always smaller than the perl-block count.
#
# CHECK IT EVERY RUN rather than remembering a number. This prints what the
# corpus currently holds:
#
#   grep -c '^```output$' $SON_CORPUS/*.md | awk -F: '{s+=$2} END {print s}'
#
# If that does not equal the `cases:` line, the parse is wrong and no result
# below it is worth reading. A number quoted from a previous run is not a
# baseline -- measured 2026-09-26, the corpus went 210 -> 213 output blocks in
# an afternoon, and a hardcoded 210 here would have read as a parse defect.
#
# COMPARES STDOUT ONLY. pvm's auditor compares stderr too and scores one case
# (025, a dropped `local $SIG{__WARN__}`) DIFFERS where this scores it correct.
# That disagreement is recorded in docs/plans/2026-09-26-the-round-trip-goal.md
# and is a known convention difference, not a defect either harness found.
#
#   perl tools/corpus-roundtrip.pl        tallies
#   perl tools/corpus-roundtrip.pl -v     each DIFFERS with emitted/got/want
use strict; use warnings;
use JSON::PP;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use SoN::Deparse;

# The corpus lives in pvm's tree, so the path is an INPUT rather than a
# constant -- a stale checkout is the failure mode pvm and I have each hit, and
# baking one path in makes it invisible.
my $C = $ENV{SON_CORPUS}
     // '/home/perigrin/dev/pvm/.claude/worktrees/pu/conformance/mdtest';
die "no corpus at $C (set SON_CORPUS)\n" unless -d $C;
my $dir = tempdir(CLEANUP => 1);
my @cases;

for my $md (sort glob "$C/*.md") {
    open my $fh, '<', $md or die $!;
    my @lines = <$fh>; close $fh;
    my ($i, $cur) = (0, undef);
    while ($i < @lines) {
        my $l = $lines[$i];
        if ($l =~ /^```perl\s*$/) {
            my @body;
            $i++;
            push @body, $lines[$i++] while $i < @lines && $lines[$i] !~ /^```\s*$/;
            $i++;
            $cur = { file => $md, src => join('', @body) };
            next;
        }
        if ($l =~ /^```output\s*$/ && $cur) {
            my @body;
            $i++;
            push @body, $lines[$i++] while $i < @lines && $lines[$i] !~ /^```\s*$/;
            $i++;
            $cur->{want} = join('', @body);
            push @cases, $cur;
            $cur = undef;
            next;
        }
        $i++;
    }
}

printf "cases: %d\n", scalar @cases;
my %tally;
my @differs;
my @unrendered;
my $n = 0;

# ALL of it, joined: the first line of a multi-line error is not its verdict
# often enough to be trusted to decide one.
sub whole_message {
    my @l = grep { length } split /\n/, $_[0];
    return @l ? join(q{ | }, @l) : q{no message};
}
for my $c (@cases) {
    $n++;
    my $id = sprintf "%03d", $n;
    my $f = "$dir/c$id.pl";
    open my $o, '>', $f or die $!; print $o $c->{src}; close $o;

    my $json = qx($^X -I$FindBin::Bin/../lib -MO=SoN,json,not_package=SoN $f 2>$dir/e);
    my $data = eval { JSON::PP->new->decode($json) };
    unless ($data && $data->{methods}) {
        $tally{NOJSON}++;
        push @unrendered, [$id, 'NOJSON', $c->{file}, whole_message(do { local(@ARGV, $/) = "$dir/e"; <> })];
        next;
    }

    my $d = SoN::Deparse->new;
    my $out = eval { $d->render($data) };
    unless (defined $out) {
        $tally{REFUSED}++;
        push @unrendered, [$id, 'REFUSED', $c->{file}, whole_message($d->gap // $@)];
        next;
    }

    my $g = "$dir/g$id.pl";
    open my $o2, '>', $g or die $!; print $o2 $out; close $o2;
    my $got = qx($^X $g 2>/dev/null </dev/null);

    if ($got eq $c->{want}) { $tally{ROUNDTRIP}++ }
    else {
        $tally{DIFFERS}++;
        # A DIFFERS whose emission does not even compile is the deparser's
        # defect, not a semantic one, and it is counted on its own line.
        qx($^X -c $g 2>/dev/null);
        $tally{EMITS_INVALID_PERL}++ if $?;
        push @differs, [$id, $c->{file}, $out, $got, $c->{want}];
    }
}
$tally{EMITS_INVALID_PERL} //= 0;
printf "%-18s %d\n", $_, $tally{$_} for sort keys %tally;
if (@ARGV && $ARGV[0] eq '-v') {
    # ONE LINE PER UNRENDERED CASE, with its cause. A count cannot say which
    # case moved; the tier-2 census learned that first.
    printf "STATUS %s %-7s %s: %s\n", $_->[0], $_->[1], $_->[2] =~ s{.*/}{}r, $_->[3]
        for @unrendered;
    for my $d (@differs) {
        printf "\n=== %s %s ===\n--- emitted ---\n%s--- got ---\n%s--- want ---\n%s",
            $d->[0], $d->[1], $d->[2], $d->[3], $d->[4];
    }
}
