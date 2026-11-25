#!/usr/bin/perl
# ABOUTME: How often B::SoN's fast path for an alias holds (a value) or fails (a place), by binder --
# ABOUTME: a call's argument, an alias list's item, a foreach iterator -- over chalk's lib wires.
#
#   tools/alias-fastpath.pl --chalk DIR [--jobs N]
#
# Each lib/**/*.pm of DIR is compiled as tools/wire-verify.pl --chalk does,
# with SON_ALIAS_STATS=1 (SoN::FromOptree prints its counts at exit).
use v5.42.0;
use Getopt::Long;
use FindBin;
use File::Find;

my ( $chalk, $jobs ) = ( undef, 2 );
GetOptions( 'chalk=s' => \$chalk, 'jobs=i' => \$jobs ) or die "usage: $0 --chalk DIR [--jobs N]\n";
die "usage: $0 --chalk DIR [--jobs N]\n" unless $chalk && -d "$chalk/lib";
my $root = "$FindBin::Bin/..";
my @files;
find( { no_chdir => 1, wanted => sub { push @files, $File::Find::name if /\.pm\z/ } }, "$chalk/lib" );
@files = sort @files;

my ( %sum, %pid ); my ( $done, $missing ) = ( 0, 0 );
my $limit = $ENV{SON_WIRE_TIMEOUT} // 900;
my $reap = sub {
    my $pid = wait;
    my $out = delete $pid{$pid} // return;
    $done++;
    my ($line) = grep { /^ALIAS_STATS/ } do { open my $in, '<', $out or return; <$in> };
    unlink $out;
    unless ($line) { $missing++; return }
    $sum{$1} += $2 while $line =~ /(\S+)=(\d+)/g;
};
my $n = 0;
for my $f (@files) {
    $reap->() while keys %pid >= $jobs;
    my $out = "/tmp/alias-fastpath.$$." . ++$n;
    my $pid = fork // die "fork: $!";
    if ( !$pid ) {
        chdir $chalk or exit 1;
        $ENV{SON_ALIAS_STATS} = 1;
        exec 'sh', '-c', "ulimit -v 4000000; /usr/bin/timeout $limit $^X -I$root/lib -Ilib -MO=-q,SoN,json,not_package=SoN '$f' >/dev/null 2>'$out'";
    }
    $pid{$pid} = $out;
}
$reap->() while keys %pid;
say "files $done, no counts $missing";
for my $b (qw(arg call record list iter)) {
    my ( $p, $v ) = ( $sum{"$b-place"} // 0, $sum{"$b-value"} // 0 );
    my $t = $p + $v;
    say sprintf '%-5s value %6d  place %6d  proof fails %5.1f%%', $b, $v, $p, $t ? 100 * $p / $t : 0;
}
