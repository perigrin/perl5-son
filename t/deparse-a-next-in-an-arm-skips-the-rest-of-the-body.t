# ABOUTME: A `next` inside an arm skips the rest of the loop body, not just the arm,
# ABOUTME: and a rest of the body that ends in `last` leaves the loop rather than iterating.

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

# A `next if` IN AN ARM is an edge to the latch. Merged at the arm's end, the
# taken path ran the code after the arm too: 123456 for 12345, in a foreach
# or a while, and with an outer `next if` and a guarded return beside it.
round_trips(<<'P', 'a next in an arm skips the code after the arm');
sub f { my $s = ""; for my $o (1 .. 6) { if ($o > 3) { next if $o == 6 } $s .= $o } return $s }
print f(), "\n";
P

round_trips(<<'P', 'in a while loop');
sub f { my $s = ""; my $o = 0; while ($o < 6) { $o++; if ($o > 3) { next if $o == 6 } $s .= $o } return $s }
print f(), "\n";
P

round_trips(<<'P', 'beside an outer next and a guarded return');
sub f { my $s = ""; for my $o (1 .. 6) { next if $o == 5; if ($o > 3) { next if $o == 6; return "r$s" if $o == 7 } $s .= $o } return $s }
print f(), "\n";
P

round_trips(<<'P', 'with work before and after it in the arm');
sub f { my $s = ""; for my $o (1 .. 6) { if ($o > 3) { $s .= "x"; next if $o == 5; $s .= "y" } $s .= $o } return $s }
print f(), "\n";
P

round_trips(<<'P', 'two arms deep, with a continue block');
sub f { my $s = ""; for my $o (1 .. 6) { if ($o > 1) { if ($o > 3) { next if $o == 5 } } $s .= $o } continue { $s .= "," } return $s }
print f(), "\n";
P

round_trips(<<'P', 'at the top level of the program');
my $s = ""; for my $o (1 .. 6) { if ($o % 2) { next if $o > 3 } $s .= $o } print "$s\n";
P

round_trips(<<'P', 'pushing after the arm');
sub f { my @r; for my $o (1 .. 6) { if ($o > 2) { next if $o == 4; push @r, "a" } push @r, $o } return "@r" }
print f(), "\n";
P

# A REST OF THE BODY THAT ENDS IN `last` breaks: the `last` is an edge to the
# exit, and the loop iterates only along a `next`. Merged with the guard's
# arm, the `last` was dropped and the loop ran on to its other guard.
round_trips(<<'P', 'a trailing last after an arm that nexts');
sub f { my ($c) = @_; my $n = 0; while (1) { $n++; last if $n > 9; if ($c) { next } last } return $n }
print f(1), f(0), "\n";
P

round_trips(<<'P', 'with work before the trailing last');
sub f { my ($c) = @_; my $n = 0; while (1) { $n++; last if $n > 9; if ($c) { next } $n += 100; last } return $n }
print f(1), f(0), "\n";
P

round_trips(<<'P', 'after a next if');
sub f { my ($c) = @_; my $n = 0; while (1) { $n++; last if $n > 9; next if $c; $n += 100; last } return $n }
print f(1), f(0), "\n";
P

round_trips(<<'P', 'a chain walk whose arm breaks or nexts');
sub f { my ($cur) = @_; my $n = 0; while (1) { $n++; last if $n > 9; if (ref $cur eq "ARRAY") { my $h = $cur->[0]; last unless defined $h; $cur = $h; next } last } return $n }
print f([[[undef]]]), f(3), "\n";
P

round_trips(<<'P', 'a counted loop whose rest breaks after a next if');
sub f { my $n = 0; for my $i (1 .. 5) { $n++; next if $i < 3; $n += 10; last } return $n }
print f(), "\n";
P

round_trips(<<'P', 'with a continue block');
sub f { my $n = 0; my $i = 0; while ($i++ < 5) { $n++; next if $i < 3; $n += 10; last } continue { $n += 1000 } return $n }
print f(), "\n";
P

# An endless loop that leaves by the function's exit returns its value from
# an arm that breaks.
round_trips(<<'P', 'an arm that prints and breaks an endless loop');
sub f { my $n = 0; while (1) { $n++; last if $n > 9; if ($n > 3) { print "x"; last } } return $n }
print f(), "\n";
P

# A `last LABEL` from a nested loop out of such a loop has no payment to make
# and no label to name: it refuses, naming why. Unrefused it emitted a jump
# to a label the loop never carried, and died where perl printed 4.
{
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of(<<'P') // {});
sub f { my $n = 0; W: while (1) { $n++; last if $n > 9; for my $i (1 .. 3) { last W if $n == 4 } } return $n }
print f(), "\n";
P
    is $out, undef, 'a last LABEL out of an endless loop does not render';
    like $d->gap // '', qr/a `last LABEL` out of an endless loop that leaves by the function's exit/,
        'and names its cause';
}

done_testing;
