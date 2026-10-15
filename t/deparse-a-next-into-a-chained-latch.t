# ABOUTME: Two or more `next` edges merge into the latch one Region at a time; a `next`# ABOUTME: into an earlier Region of that chain pays every later one it passes through.

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


# The first next paid only its own Region's value, and the latch read the
# second's: 1-3-4b5-6- for perl's 1-2a3-4b5-6-.
round_trips(q{my $s=''; for my $i (1..6) { $s .= $i; if ($i == 2) { $s .= "a"; next } if ($i == 4) { $s .= "b"; next } $s .= "-" } print "$s\n";},
    'two next blocks, then a fall-through');
round_trips(q{my $s=''; for my $i (1..7) { $s .= $i; if ($i == 2) { $s .= "a"; next } if ($i == 4) { $s .= "b"; next } if ($i == 6) { $s .= "c"; next } $s .= "-" } print "$s\n";},
    'three next blocks');
round_trips(q{my ($s,$n)=('',0); my $i=0; while ($i < 6) { $i++; $n++; if ($i == 2) { $s .= "a"; next } if ($i == 4) { $n += 10; next } $s .= "-" } print "$s $n\n";},
    'a while loop with two values');
round_trips(q{my $s=''; for my $i (1..6) { next if $i == 1; $s .= $i; if ($i == 4) { $s .= "!"; next } $s .= "-"; next } print "$s\n";},
    'next if, then a next block, then a trailing next');
round_trips(q{my $s=''; for my $i (1..6) { $s .= $i; if ($i == 2) { $s .= "a"; next } if ($i == 4) { $s .= "b"; next } $s .= "-" } continue { $s .= "c" } print "$s\n";},
    'two next blocks with a continue block');

done_testing;
