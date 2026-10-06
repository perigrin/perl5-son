# ABOUTME: `(LIST) x N` repeats the list -- N copies of its elements -- while `STR x N`
# ABOUTME: repeats the string; perl marks the list form OPpREPEAT_DOLIST.

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


# THE LIST FORM WAS BUILT AS THE STRING FORM: `("x") x 3` gave one string,
# "xxx", where perl gives three elements, and `(1, 2) x 2` gave "1", "22".
# perl tells them apart by a private flag on the repeat op, not by its
# operands.
round_trips(<<'SRC', 'a one-element list repeated');
my $n = 3; my @c = ("x") x $n; print scalar(@c), ":@c\n";
SRC

round_trips(<<'SRC', 'a two-element list repeated');
my $n = 2; my @c = (1, 2) x $n; print "@c\n";
SRC

round_trips(<<'SRC', 'a string repeated, unchanged');
my $n = 3; print "-" x $n, "\n";
SRC

round_trips(<<'SRC', 'a list repeated as a call argument');
sub count { scalar @_ } my $n = 4; print count((0) x $n), "\n";
SRC

done_testing;
