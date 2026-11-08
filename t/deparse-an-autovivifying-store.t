# ABOUTME: a deref for a store autovivifies: a `my` scalar undef there is a new hash or array,
# ABOUTME: and an undef element dereferenced for a store gets one stored into it first.

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

round_trips(q{my $r; $r->{a} = 1; print join(",", keys %$r), "\n";}, 'a hash element stored through an undef scalar');
round_trips(q{my $r; $$r{a} = 2; print $r->{a}, "\n";}, 'the same, spelled $$r{a}');
round_trips(q{my $r; $r->[1] = 5; print scalar(@$r), "\n";}, 'an array element stored through an undef scalar');
round_trips(q{my $r = {}; $r->{a}{b} = 3; print $r->{a}{b}, "\n";}, 'a hash two levels down');
round_trips(q{my $r; push @{$r->{l}}, 4; print "@{$r->{l}}\n";}, 'a push onto an array an undef scalar\'s element holds');
round_trips(q{my $r = {}; push @{$r->{l}}, 4; push @{$r->{l}}, 5; print "@{$r->{l}}\n";}, 'two pushes onto an element\'s array');
round_trips(q{my %h; push @{$h{l}}, 4; print "@{$h{l}}\n";}, 'a push onto a named hash\'s element');
round_trips(q{my %h; $h{x}{y} = 6; $h{x}{z} = 7; print join(",", map { "$_=$h{x}{$_}" } sort keys %{$h{x}}), "\n";}, 'a named hash two levels down, twice');
round_trips(q{my @a; $a[0][1] = 8; print scalar(@{$a[0]}), "\n";}, 'an array of arrays');
round_trips(q{for my $i (1, 2) { my $r; $r->{n} = $i; print $r->{n} } print "\n";}, 'a fresh hash each pass of a loop');

done_testing;
