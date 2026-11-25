#!/usr/bin/perl
# inv.pl PRODUCER CHALK CENSUS_OUT DEPARSE_OUT > gaps.tsv
# Every refusal site in both libs, its static message, and whether a corpus case
# (pvm ir `refused:`, chalk-copy son `refused:`, census GAP, deparser REFUSED) or
# an audit probe (chalk's BASELINE.tsv) shows it.
use v5.36;
my ($P, $C, $census, $deparse) = @ARGV;

# --- sites
my @sites;
sub static_prefix ($rest, $q) {
    my $s = '';
    while (length $rest) {
        if ($rest =~ s/\A\\(.)//s) { $s .= $1; next }
        last if substr($rest,0,1) eq $q;
        last if $q eq '"' && $rest =~ /\A[\$\@][\w{:]/;
        $s .= substr($rest, 0, 1, '');
    }
    $s =~ s/%[sd]/ /g;
    return $s;
}
for my $f (split /\n/, `grep -rnE 'GAP: |\\bout\\(' $P/lib $C/lib/Chalk`) {
    my ($file, $line, $text) = $f =~ /\A([^:]+):(\d+):(.*)\z/ or next;
    next if $text =~ /\A\s*#/;
    my ($kind, $msg);
    if ($text =~ /(["'])GAP: (.*)/) {
        $msg = static_prefix($2, $1);
        $kind = $file =~ m{/Deparse\.pm\z} ? 'deparser'
              : index($file, $P) == 0 ? 'producer' : 'chalk';
    }
    elsif ($file =~ m{Target/LLVM} && $text =~ /\bout\((["'])(.*)/) {
        $msg = static_prefix($2, $1);
        $kind = 'T2';
    }
    else { next }
    $msg =~ s/\s+/ /g; $msg =~ s/\s+\z//;
    (my $rel = $file) =~ s{\A\Q$P\E/}{producer:}; $rel =~ s{\A\Q$C\E/}{chalk:};
    push @sites, { kind => $kind, msg => $msg, at => "$rel:$line" };
}

# --- what the corpus shows, by case
my @seen;    # [where, text]
sub cases_of ($md) {      # title of each perl block in order, as the census counts cases
    open my $fh, '<', $md or die; my ($t, @c, $pending) = ('?');
    while (<$fh>) {
        $t = $1 if /^## (.*)/;
        if (/^```perl\s*$/) { $pending = $t }
        elsif (/^```output\s*$/ && defined $pending) { push @c, $pending; undef $pending }
    }
    return @c;
}
my @order;
for my $md (sort glob "$P/t/corpus/mdtest/pvm/*.md") {
    (my $b = $md) =~ s{.*/}{};
    push @order, map { "$b: $_" } cases_of($md);
}
for my $md (sort(glob("$P/t/corpus/mdtest/pvm/*.md")), sort(glob("$P/t/corpus/mdtest/chalk/*.md"))) {
    (my $b = $md) =~ s{.*/t/corpus/mdtest/}{};
    open my $fh, '<', $md or die; my ($t, $in) = ('?', 0);
    while (<$fh>) {
        $t = $1 if /^## (.*)/;
        if (/^refused: \[/) { $in = 1; next }
        if ($in) { $in = 0, next if /^\]/; push @seen, ["$b: $t", $_] }
    }
}
for ([$census, 'census'], [$deparse, 'deparser']) {
    my ($f, $how) = @$_;
    open my $fh, '<', $f or die "$f: $!";
    while (<$fh>) {
        next unless /^STATUS (\d+) (\w+)\s+(\S+): (.*)/;
        next if $2 eq 'ROUNDTRIP' || $2 eq 'DIFFERS';
        push @seen, [($order[$1 - 1] // "$3 #$1") . " ($how)", $4];
    }
}
my @probe;
open my $bt, '<', "$C/t/data/audit-probes/BASELINE.tsv" or die;
while (<$bt>) { my ($n, $v, $why) = split /\t/; push @probe, [$n, $why] if ($why // '') =~ /\S/ }

sub norm ($s) { $s =~ s/\\"/"/g; $s =~ s/\s+/ /g; $s }
$_->[1] = norm($_->[1]) for @seen, @probe;

print join("\t", qw(message file:line kind corpus_case probe)), "\n";
my (%n, %uniq);
for my $s (@sites) {
    my $m = $s->{msg};
    my ($case, $probe) = ('NONE', '');
    if (length($m) < 20) { $case = 'DYNAMIC' }
    else {
        my ($hit) = grep { index($_->[1], $m) >= 0 } @seen;
        $case = $hit->[0] if $hit;
        my ($ph) = grep { index($_->[1], $m) >= 0 } @probe;
        $probe = $ph->[0] if $ph;
    }
    $n{$s->{kind}}{$case eq 'NONE' ? 'none' : $case eq 'DYNAMIC' ? 'dynamic' : 'covered'}++;
    $uniq{$m}++;
    print join("\t", $m, $s->{at}, $s->{kind}, $case, $probe), "\n";
}
for my $k (sort keys %n) {
    printf STDERR "%-9s covered %3d  none %3d  dynamic %3d\n", $k, map { $n{$k}{$_} // 0 } qw(covered none dynamic);
}
printf STDERR "sites %d, distinct messages %d\n", scalar @sites, scalar keys %uniq;
