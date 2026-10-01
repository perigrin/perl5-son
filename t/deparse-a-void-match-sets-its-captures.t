# ABOUTME: A match in void context whose captures are read -- `$s =~ /(.)/; ... $1` --
# ABOUTME: is placed where it runs, not dropped as a value nobody consumed.

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

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    if (!$data || $err =~ /skipped/) {
        fail "$name: translates"; diag $err; return;
    }
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

# THE MATCH VANISHED. In void context its only use is setting $1 and its
# kin, and a RegexCapture reading it names it as an input -- but nothing put
# the match on the control chain, so nothing emitted it and `$1` read
# whatever came before. Found under chalk's Bootstrap::Terminal, whose
# fixed pos() still could not bring its captures back.
round_trips(<<'SRC', 'a void match, then its capture');
my $s = "xy"; $s =~ /(.)/; print "$1\n";
SRC

round_trips(<<'SRC', 'a void match in a sub, its capture returned');
sub f { my $s = shift; $s =~ /(.)$/; return $1 } print f("xy"), f("ab"), "\n";
SRC

round_trips(<<'SRC', 'a void \G match after pos() on a parameter');
use v5.42;
sub f ($s, $at = 0) { pos($s) = $at; $s =~ /\G(.)/; return $1 }
print f("xyz"), f("xyz", 2), "\n";
SRC

done_testing;
