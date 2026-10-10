# ABOUTME: $#x of the slurpy array in a mixed list destructure is the last index, not
# ABOUTME: length(@x): the av2arylen operand is an array by the optree, whatever its stamp.

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


round_trips('sub g { my ($k, @x) = @_; return $#x } print g(1,2,3), "\n"; print g(1,2,3,4,5), "\n";',
    'the repro: $#x returned from a sub');
round_trips('sub g { my ($k, @x) = @_; my $n = $#x; return $n } print g(1,2,3), "\n"; print g(9), "\n";',
    '$#x stored in a scalar, including the empty slurpy');
round_trips('sub g { my ($k, @x) = @_; return "$k:$#x" } print g(1,2,3,4), "\n";',
    '$#x interpolated in a string');
round_trips('sub g { my ($k, @x) = @_; my $s = 0; for my $i (0..$#x) { $s += $x[$i] } return $s } print g(1,2,3,4), "\n";',
    '$#x as a loop bound');
round_trips('my ($k, @x) = (1, 2, 3, 4); print $#x, "\n";',
    '$#x after a top-level mixed destructure');
round_trips('our @x; my $k; ($k, @x) = (1, 2, 3); print $#x, "\n";',
    '$#x of a package array in a mixed destructure');
round_trips(q{sub g { my ($k, @x) = @_; push @x, $k; return $#x } print g(1,2,3), "\n";},
    q{$#x after a push onto the slurpy});
round_trips('sub g { my ($k, @x) = @_; return $#x + 1 == @x ? "ok" : "no" } print g(1,2,3), "\n";',
    '$#x compared with the count');

done_testing;
