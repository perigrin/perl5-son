# ABOUTME: The countof idiom over a list-valued ternary counts the chosen arm's elements
# ABOUTME: in the emission, rather than yielding the arm's last element.

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


round_trips('my $c=1; my $n = () = ($c ? 7 : ()); print "$n\n";',
    q{the repro: a one-element arm counts 1});
round_trips('my $c=0; my $n = () = ($c ? 7 : ()); print "$n\n";',
    q{the empty arm counts 0});
round_trips('sub f { my $c = shift; my $n = () = ($c ? 7 : ()); return $n } print f(0), f(1), "\n";',
    q{inside a sub, both arms});
round_trips('my $c=1; my $x="a"; my $n = () = ($c ? $x : ()); print "$n\n";',
    q{a lexical scalar arm counts 1, not its value});
round_trips('my %h=(a=>1,b=>2); my $c=1; my $n = () = ($c ? %h : ()); print "$n\n";',
    q{a hash arm counts its flattened pairs});
round_trips('my $c=1; my $n = scalar(my @t = ($c ? 7 : ())); print "$n\n";',
    q{scalar of a list assignment to an array});
round_trips('our $n; my $c=1; $n = () = ($c ? 7 : ()); print "$n\n";',
    q{a package scalar target});
round_trips('my %h; my $c=1; $h{n} = () = ($c ? 7 : ()); print "$h{n}\n";',
    q{a hash element target});
round_trips('my $c=1; my $r = [9]; my $n = () = ($c ? $r->[0] : ()); print "$n\n";',
    q{an element-through-a-reference arm});
round_trips('for my $c (0..2) { my $n = () = ($c ? $c : ()); print "$n\n" }',
    q{in a loop, arm chosen by the loop variable});

round_trips('my $c=1; my $n = (my @t = ($c ? 7 : ())); print "$n @t\n";',
    q{a list assignment to a fresh array, read as a scalar, counts});
round_trips('my $c=0; my @t; my $n = (@t = ($c ? 7 : ())); print "$n\n";',
    q{a list assignment to a declared array, empty arm, counts 0});

done_testing;
