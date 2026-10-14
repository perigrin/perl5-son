# ABOUTME: Two lexicals of one name in one sub are two variables: a write to the inner
# ABOUTME: `my $s` must not reach the outer `$s`. Each case runs both programs and compares.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub round_trips ($src, $name) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    my $data = eval { JSON::PP->new->decode($j) } or return fail "$name: translates";
    my $d = SoN::Deparse->new;
    my $out = $d->render($data) // return fail "$name: renders: " . ($d->gap // '?');
    is run_perl($out), run_perl($src), $name or diag $out;
}

# THE PadAccess FOR EACH IS ONE NODE. Its identity leaves out the pad index on
# purpose (one variable, two subs, two indices), so the inner `$s` and the
# outer one hash-consed together and `$s += 1` inside the block rebound the
# OUTER slot: perl 1, emitted 2.
round_trips(<<'SRC', '+= on a shadowing my');
my $s=0; { my $s = 50; $s += 1 } $s += 1; print "$s\n";
SRC
round_trips(<<'SRC', '++ on a shadowing my');
my $s=0; { my $s = 50; $s++ } $s++; print "$s\n";
SRC
round_trips(<<'SRC', 'prefix ++ on a shadowing my');
my $s=0; { my $s = 50; ++$s } ++$s; print "$s\n";
SRC
round_trips(<<'SRC', '*= on a shadowing my');
my $s=1; { my $s = 50; $s *= 2 } $s *= 3; print "$s\n";
SRC
round_trips(<<'SRC', 'a shadowing my in an if arm');
my $s=0; if ($s == 0) { my $s = 50; $s += 1 } $s += 1; print "$s\n";
SRC
round_trips(<<'SRC', 'a shadowing my in a while body');
my $s=0; my $j=0; while ($j<2) { my $s = 9; $s += 1; $j++ } $s += 1; print "$s\n";
SRC
round_trips(<<'SRC', 'sibling blocks with one name');
my $o=""; { my $m = 1; $m += 1; $o .= $m } { my $m = 5; $m += 1; $o .= $m } print "$o\n";
SRC

done_testing;
