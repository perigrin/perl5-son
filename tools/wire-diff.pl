#!/usr/bin/env perl
# ABOUTME: Compares two wire caches (tools/wire-verify.pl --wires layout, SOURCE/NAME.json)
# ABOUTME: file by file and graph by graph; prints what differs, exits 1 when anything does.
use v5.42.0;
use JSON::PP;
use Getopt::Long;

# usage: wire-diff.pl [--quiet] OLD NEW
#   A wire names the file a die is in, and the corpus cases are written to a
#   fresh temporary directory per run, so `/tmp/XXXX/NNN.pl` is compared as
#   `NNN.pl`, and a probe as its path from docs/research. A file missing on one side is a difference; a file empty on both
#   (no wire: the producer refused or died) is not.
#   Prints `SOURCE/NAME: graph G` per differing graph, then a count line.
my $quiet;
GetOptions( quiet => \$quiet ) && @ARGV == 2 or die "usage: $0 [--quiet] OLD NEW\n";
my ( $old, $new ) = @ARGV;
my $json = JSON::PP->new->utf8->canonical;

sub load ($f) {
    return undef unless -s $f;
    open my $fh, '<', $f or die "$f: $!";
    local $/;
    my $t = <$fh>;
    $t =~ s{/tmp/[^/"]+/(\d+\.pl)}{$1}g;
    $t =~ s{"[^"]*/(docs/research/[^"]+\.pl)"}{"$1"}g;    # a probe, under whichever checkout
    return eval { $json->decode($t) } // { undecodable => 1 };
}

sub graphs ($w) {
    return {} unless $w;
    my %g = map { ( "method $_" => $w->{methods}{$_} ) } keys( ( $w->{methods} // {} )->%* );
    my $i = 0;
    $g{ 'phase ' . $i++ } = $_ for ( $w->{phase_blocks} // [] )->@*;
    my %rest = %$w;
    delete @rest{qw(methods phase_blocks)};
    $g{'(top level)'} = \%rest;
    return \%g;
}

my %files;
for my $root ( $old, $new ) {
    $files{ $_ =~ s{^\Q$root\E/}{}r } = 1 for glob "$root/*/*.json";
}
my ( $n, $differ ) = ( 0, 0 );
for my $f ( sort keys %files ) {
    $n++;
    my ( $a, $b ) = ( load("$old/$f"), load("$new/$f") );
    next if !$a && !$b;
    if ( !$a || !$b ) { $differ++; say "$f: wire only in " . ( $a ? 'OLD' : 'NEW' ) unless $quiet; next }
    my ( $ga, $gb ) = ( graphs($a), graphs($b) );
    my @d = grep {
        !defined $ga->{$_} || !defined $gb->{$_} || $json->encode( $ga->{$_} ) ne $json->encode( $gb->{$_} )
    } sort( keys %{ { %$ga, %$gb } } );
    next unless @d;
    $differ++;
    say "$f: graph $_" for $quiet ? () : @d;
}
say "# $differ of $n wires differ";
exit( $differ ? 1 : 0 );
