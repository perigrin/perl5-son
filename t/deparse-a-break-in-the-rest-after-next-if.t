# ABOUTME: A `last if` in the rest after a `next if`, with a `next` after it: the rest# ABOUTME: goes round past the break, and the latch takes the value it reached there with.

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


# The rest's fall-through past the break reaches the latch inside the nested
# if; nothing paid its value there, and every value on that path was lost (3).
round_trips(q{my $s=''; for my $i (1..5) { next if $i == 1; $s .= $i; last if $i == 3; next } print "$s\n";},
    'next if, then a rest with last if and a trailing next');
round_trips(q{my $s=''; my $i=0; while ($i < 5) { $i++; next if $i == 1; $s .= $i; last if $i == 3; next } print "$s\n";},
    'the same in a while loop');
round_trips(q{my $s=''; for my $i (1..5) { next if $i == 1; $s .= $i; if ($i == 3) { last } next } print "$s\n";},
    'the break as an if block');
round_trips(q{my $s=''; for my $i (1..5) { next unless $i > 1; $s .= $i; last unless $i < 3; next } print "$s\n";},
    'unless forms');
round_trips(q{my ($s,$n)=('',0); for my $i (1..6) { next if $i == 1; $s .= $i; $n += $i; last if $i == 4; $n++; next } print "$s $n\n";},
    'two values, one changed after the break');

# The latch is also the outer if's join; the `next` paid one name for its
# value and the latch read another (r3 for perl's r23).
round_trips(q{sub f { my $s=''; for my $i (@_) { next if $i == 1; $s .= $i; return "r$s" if $i == 3; next } return $s } print f(1..5), " ", f(1,2), "\n";},
    'a return if in the rest, then next');
round_trips(q{sub f { my $s=''; for my $i (@_) { next if $i == 1; $s .= $i; if ($i == 3) { return "r$s" } $s .= "-"; next } return $s } print f(1..5), " ", f(1,2), "\n";},
    'a return block in the rest, then more, then next');

done_testing;
