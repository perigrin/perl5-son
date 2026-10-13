# ABOUTME: A list read through a reference is the aggregate's contents where it
# ABOUTME: is written, not where its value is next spelled.

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



# A LIST READ OF A DEREFERENCED AGGREGATE is the contents at that point: a
# later push, store or call does not reach back into a copy already taken.
for my $case (
    [q{use v5.36; sub f ($x = [3,1,2]) { my @s = sort { $a <=> $b } @$x; push @$x, 0; "@s|@$x" } print f(), " ", f([2,1]), "\n";},
        'a sorted copy before a push, under an allocating default'],
    [q{use v5.36; sub g { [] } sub f ($x = g()) { my @s = sort { $a <=> $b } @$x; push @$x, 0; "@s|@$x" } print f(), " ", f([2,1]), "\n";},
        'a sorted copy before a push, under a calling default'],
    [q{use v5.36; sub f ($x) { my @s = sort { $a <=> $b } @$x; push @$x, 0; "@s|@$x" } print f([2,1]), "\n";},
        'a sorted copy before a push'],
    [q{use v5.36; sub f ($x = [3,1,2]) { my @s = reverse @$x; push @$x, 0; "@s|@$x" } print f(), " ", f([2,1]), "\n";},
        'a reversed copy before a push'],
    [q{sub f { my $x = shift; my @s = @$x; push @$x, 0; "@s|@$x" } print f([2,1]), "\n";},
        'a copy before a push'],
    [q{sub f { my $x = shift; my $n = @$x; push @$x, 0; "$n|@$x" } print f([2,1]), "\n";},
        'a count before a push'],
    [q{sub f { my $x = shift; my @s = (9, @$x); push @$x, 0; "@s|@$x" } print f([2,1]), "\n";},
        'a list holding a copy before a push'],
    [q{sub f { my $x = shift; my @s = @$x; $x->[0] = 7; "@s|@$x" } print f([2,1]), "\n";},
        'a copy before an element store'],
    [q{my $x = [2,1]; my @s = @$x; push @$x, 0; print "@s|@$x\n";},
        'a copy before a push at the top level'],
    [q{sub f { my $x = shift; push @$x, scalar(@$x); "@$x" } print f([2,1]), "\n";},
        'a count inside the push it precedes'],
) {
    round_trips(@$case);
}

done_testing;
