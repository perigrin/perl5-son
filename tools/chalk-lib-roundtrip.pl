#!/usr/bin/env perl
# ABOUTME: Census of chalk's lib/ through B::SoN: translate each module, render it
# ABOUTME: back with SoN::Deparse, and check the emitted lib/ compiles. Tallies only.
use v5.42.0;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JSON::PP;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use Getopt::Long;
use SoN::Deparse;

# A PINNED COMMIT, NOT A WORKING TREE. chalk moves on its own schedule, and a
# census of whatever its checkout holds would move the floor under the ratchet
# with no change here. `git archive` reads the commit from any clone that has
# it, so the working tree's state never enters.
my $COMMIT = '5948f648';
my $chalk  = $ENV{SON_CHALK} // "$ENV{HOME}/dev/chalk";
my $verbose = 0;
# --emit DIR keeps the emitted lib/ (DIR/emit/lib/...) and writes DIR/compiles.txt,
# one module per line that compiled with no graph skipped -- what
# tools/chalk-gate3.pl overlays onto chalk to run its tests.
my $keep;
GetOptions('chalk=s' => \$chalk, 'commit=s' => \$COMMIT, 'v' => \$verbose,
           'emit=s' => \$keep)
    or die "usage: $0 [--chalk PATH] [--commit SHA] [--emit DIR] [-v]\n";

my $snap = tempdir(CLEANUP => 1);
system("git -C '$chalk' archive '$COMMIT' lib | tar -x -C '$snap'") == 0
    or die "cannot read lib/ at $COMMIT from $chalk\n";
my $out = defined $keep ? $keep : tempdir(CLEANUP => 1);
make_path($out);
my $son = "$FindBin::Bin/../lib";

my @mods = sort split /\n/, `cd '$snap' && find lib -name '*.pm'`;
my (%tally, %why, @emitted, $skipped_graphs, @compiles);
$tally{$_} = 0 for qw(COMPILES COMPILES_PARTIAL INVALID REFUSED NOJSON);
$skipped_graphs = 0;

for my $m (@mods) {
    my $json = `cd '$snap' && $^X -I$son -Ilib -MO=-q,SoN,json,not_package=SoN $m 2>$out/err`;
    my $err = do { local (@ARGV, $/) = "$out/err"; <> } // '';
    my @skipped = $err =~ /^B::SoN: (?:skipped|INTERNAL)[^\n]*/mg;
    $skipped_graphs += @skipped;
    $why{SKIPPED}{ $_ =~ s/skipped \S+: //r =~ s/\n.*//sr }++ for @skipped;
    my $data = eval { JSON::PP->new->utf8->decode($json) };
    unless ($data) {
        $tally{NOJSON}++;
        $why{NOJSON}{ (split /\n/, $err)[0] // '?' }++;
        print "NOJSON $m\n" if $verbose;
        next;
    }
    my $d = SoN::Deparse->new;
    my $text = eval { $d->render($data) };
    unless (defined $text) {
        $tally{REFUSED}++;
        (my $g = $d->gap // $@ // '?') =~ s/\n.*//s;
        $why{REFUSED}{$g}++;
        print "REFUSED $m\n" if $verbose;
        next;
    }
    my $f = "$out/emit/$m";
    make_path(dirname($f));
    open my $fh, '>', $f or die $!; print $fh $text; close $fh;
    push @emitted, [$m, $f, scalar @skipped];
}

# EACH EMISSION COMPILES WITH THE EMITTED lib/ FIRST ON @INC, and the originals
# behind it only for the modules that did not emit -- so a module is checked
# against the others as B::SoN renders them wherever it can.
for my $e (@emitted) {
    my ($m, $f, $nskip) = @$e;
    my $c = `cd '$snap' && $^X -I$out/emit/lib -Ilib -c $f 2>&1`;
    my $status;
    if ($c =~ /syntax OK/) {
        $status = $nskip ? 'COMPILES_PARTIAL' : 'COMPILES';
        push @compiles, $m if $status eq 'COMPILES';
    }
    else {
        $status = 'INVALID';
        $why{INVALID}{ (split /\n/, $c)[0] =~ s/at \S+ line \d+.*//r }++;
    }
    $tally{$status}++;
    print "$status $m\n" if $verbose;
}

if (defined $keep) {
    open my $fh, '>', "$out/compiles.txt" or die $!;
    print $fh "$_\n" for @compiles;
    close $fh;
}

print "commit: $COMMIT\n";
print "files: ", scalar(@mods), "\n";
printf "%-18s %d\n", $_, $tally{$_} for sort keys %tally;
printf "%-18s %d\n", 'SKIPPED_GRAPHS', $skipped_graphs;
for my $k (sort keys %why) {
    my $h = $why{$k};
    print "--- $k causes\n";
    printf "%5d  %s\n", $h->{$_}, substr($_, 0, 150)
        for grep { defined } (sort { $h->{$b} <=> $h->{$a} } keys %$h)[0 .. 11];
}
