# ABOUTME: A block eval whose body begins with a branch -- a guarded die, an if -- is emitted
# ABOUTME: once, inside the eval: the branch is not also emitted before it where nothing catches.

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


round_trips(q{for my $i (1..3) { my $r = eval { die "x\n" if $i==2; 1 }; print defined $r ? "ok" : "E" } print "\n";},
    'the reported loop: a guarded die inside an eval in a loop');
round_trips(q{my $g = 1; my $r = eval { die "x\n" if $g; 1 }; print defined $r ? "ok\n" : "E $@";},
    'top level, lexical guard');
round_trips(q{our $g = 1; my $r = eval { die "x\n" unless !$g; print "after\n"; 1 }; print defined $r ? "ok\n" : "E $@";},
    'top level, package guard, unless, statements after the guard');
round_trips(q{my @a = (0, 1); for my $j (0, 1) { eval { die "e$j\n" if $a[$j] }; print $@ || "none\n" }},
    'void eval, element guard, in a loop');
round_trips(q{sub f { my $h = shift; my $r = eval { if ($h->{k}) { die "k\n" } "v" }; return $r // "E:$@" } print f({k=>1}), f({k=>0}), "\n";},
    'in a sub, reference guard, an if block as the first statement');
round_trips(q{my $n = 0; my $r = eval { if ($n) { print "n\n" } else { print "z\n" } 1 }; print "r=$r\n";},
    'an if/else that does not die still runs once');
round_trips(q{my $g = 1; my $r = eval { my $o = eval { die "in\n" if $g; 1 }; print defined $o ? "o\n" : "c $@"; die "out\n" if $g; 1 }; print defined $r ? "ok\n" : "E $@";},
    'nested evals, each guarded');
round_trips(q{print "a\n"; my $r = eval { my $o = eval { print "i\n"; 1 }; print "x\n"; die "out\n"; 1 }; print defined $r ? "ok\n" : "E $@";},
    q{nested evals that begin together: the outer one is claimed first});

done_testing;
