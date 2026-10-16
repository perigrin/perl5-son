# ABOUTME: A break out of an endless loop that leaves by the function's exit
# ABOUTME: returns the Return's own expression over the exit Phi, not the Phi bare.

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

# A SECOND `last` IN AN ENDLESS LOOP reaches the function's exit from inside
# the loop and is a `return` there. The Return reads an expression over the
# exit Phi -- an interpolation, arithmetic, a list -- and that path returned
# the Phi's input bare: 33 for "20,33", 12 for "<12>", 12 for 24.
round_trips(<<'S', 'a while (1) returning an interpolation of two Phis');
sub f { my ($x,$y)=(1,2); while (1) { ($x,$y)=($y,$x+$y); last if $x > 20; $y++; last if $y > 30 } return "$x,$y" }
print f(), "\n";
S

round_trips(<<'S', 'a for (;;) returning an interpolation');
sub f { my $y=0; for (;;) { $y++; last if $y == 2; $y += 3; last if $y > 9 } return "<$y>" }
print f(), "\n";
S

round_trips(<<'S', 'an until (0)');
sub f { my $y=0; until (0) { $y++; last if $y == 2; $y += 3; last if $y > 9 } return "<$y>" }
print f(), "\n";
S

round_trips(<<'S', 'code after the loop that the Return reads');
sub f { my $n=0; while (1) { $n++; last if $n == 2; $n += 3; last if $n > 9 } my $r = $n * 2; return $r }
print f(), "\n";
S

round_trips(<<'S', 'a returned list');
sub f { my $n=0; while (1) { $n++; last if $n == 2; $n += 3; last if $n > 9 } return ($n, $n+1) }
print join(",", f()), "\n";
S

round_trips(<<'S', 'a ternary over the exit, on both exits');
sub f { my $n=shift; while (1) { $n++; last if $n == 2; $n += 3; last if $n > 9 } return $n > 10 ? "big" : "small" }
print f(0), f(1), "\n";
S

round_trips(<<'S', 'two Phis, one the Return reads under an interpolation');
sub f { my $n=0; my $s="a"; while (1) { $n++; last if $n == 3; $n += 3; last if $n > 9 } return "<$n>" . $s }
print f(), "\n";
S

# THE Phi THE Return READS AS IS still returns its input.
round_trips(<<'S', 'a Return of the Phi itself');
sub f { my $n=0; while (1) { $n++; last if $n == 2; $n += 3; last if $n > 9 } return $n }
print f(), "\n";
S

done_testing;
