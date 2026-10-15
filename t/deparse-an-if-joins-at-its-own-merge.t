# ABOUTME: An if whose nested arm ends in `next` joins at its own merge Region, not at the
# ABOUTME: latch the next reaches first: the fall-through pays the merge, then the latch.

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

# The emission must also be QUIET: a second `my @e` in one scope is a "masks

sub emits_quietly ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}

# `next if A; if (B) { ...; next } ...` took the latch for If A's join, and
# the fall-through paid neither (a3N for perl's a2b2-a3Na4b4a5b5-a6b6-).
round_trips(q{my $s=''; for my $i (1..6) { next if $i == 1; $s .= "a$i"; if ($i == 3) { $s .= 'N'; next } $s .= "b$i"; next if $i == 4; $s .= '-' } print "$s\n";},
    'next-if, an if ending in next, a second next-if');
round_trips(q{my $s=''; for my $i (1..6) { next if $i == 1; if ($i == 3) { $s .= 'N'; next } $s .= 'b'; next if $i == 4; $s .= '-' } print "$s\n";},
    'next-if, then an if ending in next');
round_trips(q{my $s=''; for my $i (1..6) { next if $i == 1; if ($i == 3) { $s .= 'N'; next } $s .= 'b' } print "$s\n";},
    'next-if, then an if ending in next, nothing after');
round_trips(q{my $s=''; my $i=0; while ($i < 7) { $i++; next unless $i % 2; if ($i == 3) { $s .= 'N'; next } $s .= $i } print "$s\n";},
    'next-unless in a while');
round_trips(q{my ($s,$n)=('',0); for my $i (1..6) { next if $i == 2; $n++; if ($i == 4) { $s .= 'N'; next } $s .= $n } continue { $s .= ',' } print "$s $n\n";},
    'next-if, an if ending in next, a continue block');
# Two nexts merge into chained latches: the latch nearer the walk is
# still not the join (T3FT6 for perl's 2.T34FT67.8.).
round_trips(q{my $s=''; for my $i (1..8) { next if $i == 1; if ($i % 3 == 0) { $s .= "T$i"; next } elsif ($i == 5) { $s .= 'F'; next } $s .= $i; next if $i == 4; $s .= '.' } print "$s\n";},
    'next-if, an if/elsif both ending in next, a second next-if');
round_trips(q{my $s=""; for my $i (1..8) { next if $i == 1; if ($i % 3 == 0) { $s .= "T$i"; next } if ($i == 5) { $s .= "F"; next } $s .= $i } print "$s\n";},
    'next-if, then two ifs ending in next');
round_trips(q{my $s=""; for my $i (1..4) { for my $j (1..3) { next if $j == 1; if ($i == $j) { $s .= "="; next } $s .= "$i$j" } $s .= ";" } print "$s\n";},
    'the same shape in an inner loop');
emits_quietly(q{my $s=''; for my $i (1..6) { next if $i == 1; if ($i == 3) { $s .= 'N'; next } $s .= 'b'; next if $i == 4; $s .= '-' } print "$s\n";},
    'next-if, then an if ending in next');

done_testing;
