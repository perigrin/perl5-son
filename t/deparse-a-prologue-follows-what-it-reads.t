# ABOUTME: Declarations the renderer hoists above the chain come in dependency order: a
# ABOUTME: named array built from a parameter follows the binding of that parameter.

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


# THE PROLOGUE EMITTED EVERY NAMED AGGREGATE, THEN EVERY FLOATING BINDING.
# `my @c = (1 .. $n)` after an early-return guard reads $n, which the later
# `my ($n) = @_` declares: hoisted first, it read an undeclared $n.
# chalk's Schedule::Elaborate has the shape.
round_trips(<<'SRC', 'a named array built from a parameter after a guard');
sub f { my ($n) = @_; return 0 unless $n; my @c = (1 .. $n); return scalar(@c) }
print f(0), f(3), "\n";
SRC

round_trips(<<'SRC', 'a range from a parameter after a bare return');
sub chain { my ($n) = @_; return unless defined $n; my @c = (1 .. $n); return @c }
my @a = chain(3); print scalar(@a), ":@a\n";
SRC

# AND THE OTHER WAY ROUND STILL HOLDS: a binding that reads a named array
# follows the array.
round_trips(<<'SRC', 'a binding that reads an array');
sub f { my ($k) = @_; return "none" unless $k; my @a = (1, 2, $k); my ($x, $y, $z) = @a; return "$x$y$z" }
print f(0), f(7), "\n";
SRC

done_testing;
