# ABOUTME: A `last LABEL` ending an if/else arm in a nested loop leaves the loop it names,# ABOUTME: whether the other arm stays, goes round by `next`, or leaves as well.

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


# Recorded as a break of the inner loop, the outer loop ran on (11 12 21 22 31 32).
round_trips(q{my $s=''; O: for my $i (1..3) { for my $j (1..3) { $s .= "$i$j "; if ($j == 2) { last O } else { next } } } print "$s\n";},
    'last OUTER beside next');
round_trips(q{my $s=''; O: for my $i (1..3) { for my $j (1..3) { if ($j==2) { last O } else { $s.="$i$j "; next } } } print "$s\n";},
    'last OUTER beside a block ending in next');
round_trips(q{my $s=''; O: for my $i (1..3) { $s.='<'; for my $j (1..3) { if ($i==2) { last O } else { $s.="$i$j"; next } } $s.='>' } print "$s\n";},
    'last OUTER skips the rest of the outer body');
round_trips(q{my $s=''; O: for my $i (1..3) { for my $j (1..3) { $s .= "$i$j "; if ($j == 2) { next } else { last O } } } print "$s\n";},
    'next beside last OUTER');
round_trips(q{my $s=''; O: for my $i (1..3) { for my $j (1..3) { if ($j == 2) { last O } else { $s .= "$i$j " } } } print "$s\n";},
    'last OUTER beside an arm that stays');
round_trips(q{my $s=''; O: for my $i (1..3) { for my $j (1..3) { $s .= "$i$j "; if ($j == 2) { $s.="x"; last O } } } print "$s\n";},
    'a one-armed if whose block ends in last OUTER');
round_trips(q{my $s=''; O: for my $i (1..3) { for my $j (1..3) { if ($i == 2) { $s.="x"; last O } $s .= "$i$j " } $s .= "|" } print "$s\n";},
    'the same before the rest of the inner body');
# Both arms leave and neither goes round: the inner body has no back edge.
graph_of(q{my $s=''; O: for my $i (1..3) { for my $j (1..3) { $s .= "$i$j "; if ($j == 2) { last O } else { last } } $s .= '|' } print "$s\n";});
like producer_stderr(), qr/GAP: an if\/else in a loop body whose arms all leave, none by `next`/,
    'last OUTER beside a plain last refuses by name';

done_testing;
