# ABOUTME: perl's forced-main names -- @INC, %ENV, @ARGV, STDIN and the rest -- are spelled
# ABOUTME: bare: the same variable from any package, and the spelling chalk's grammar reads.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}


# THE SAME VARIABLE, TWO SPELLINGS. perl puts @INC, %ENV, @ARGV and the
# standard handles in main whichever package names them, so `@INC` and
# `@main::INC` agree everywhere. Chalk's grammar reads only the first: it has
# no package-qualified aggregate, and chalk's perl-recognize-phase5.t, which
# recognises every module under lib/Chalk, rejected the emitted
# Bootstrap::Runtime at `scalar(@main::INC)`.
sub emitted ($src) {
    my $data = graph_of($src) or return;
    return SoN::Deparse->new->render($data);
}

round_trips(<<'SRC', '@INC from another package');
package Finder { sub count { scalar(@INC) > 0 ? "some" : "none" } }
print Finder::count(), "\n";
SRC

round_trips(<<'SRC', '%ENV and @ARGV');
package P { sub f { my $n = 0; for my $k (sort keys %ENV) { $n++ if $k eq "HOME" } return $n . scalar(@ARGV) } }
print P::f(), "\n";
SRC

# keys %ENV took the gv's name string for the hash -- `keys("main::ENV")` --
# because the package-hash path excluded ENV for its one special form.
round_trips(<<'SRC', 'keys %ENV and exists $ENV{K}');
my $n = 0; for my $k (sort keys %ENV) { $n++ if $k eq "HOME" } my $e = exists $ENV{HOME} ? 1 : 0; print "$n$e\n";
SRC

my $out = emitted(<<'SRC') // '';
my $n = scalar(@INC); my $h = exists $ENV{HOME} ? 1 : 0; print "$n $h @ARGV\n";
SRC
unlike $out, qr/main::(?:INC|ENV|ARGV)\b/, 'no forced-main name is qualified';
like $out, qr/\@INC\b/, '@INC is spelled bare';

done_testing;
