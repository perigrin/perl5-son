# ABOUTME: A guarded store into a shared or package scalar, after a `next` guard in a
# ABOUTME: loop body, runs only when its own guard holds.

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


# AFTER A `next` GUARD THE REST OF THE BODY IS WALKED AS AN ARM, and the arm
# walker's branch handler did not count a store into a shared lexical or a
# package scalar as an effect: no If was built, the store hung off the
# guard's continuation beside the latch, and the graph refused "a control
# node with 2 successors". A sub-local counter was never affected.
round_trips(<<'SRC', 'a shared lexical, block if');
my $n = 0; sub f { for my $x (@_) { next unless $x > 1; if ($x > 2) { $n++ } } $n }
print f(1, 3, 0, 5, 2), "\n";
SRC

round_trips(<<'SRC', 'a shared lexical, postfix if');
my $n = 0; sub f { for my $x (@_) { next unless $x > 1; $n++ if $x > 2 } $n }
print f(1, 3, 0, 5, 2), "\n";
SRC

round_trips(<<'SRC', 'a package scalar');
our $n = 0; sub f { for my $x (@_) { next unless $x > 1; if ($x > 2) { $n += $x } } return $n }
print f(1, 3, 0, 5, 2), "\n";
SRC

round_trips(<<'SRC', 'after a call-guarded next');
my $n = 0; sub g { $_[0] } sub f { for my $x (@_) { next unless defined $x && g($x) > 1; if ($x > 2) { $n++ } } $n }
print f(1, 3, undef, 5, 2), "\n";
SRC

done_testing;
