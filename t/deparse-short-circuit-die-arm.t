# ABOUTME: A `//`, `||` or `&&` whose right side dies, inside an if/else arm, round
# ABOUTME: trips: the die runs on its own Proj and the value is the left side.

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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK
//mr;
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
        my $g = $d->gap // '(no reason)'; $g =~ s/
.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---
$out--- got ---
$got--- want ---
$want";
}
round_trips(<<'P', 'my $r = E // die, in an arm');
sub f { my ($h) = @_; if ($h->{m}) { my $r = $h->{n} // die "no n\n"; return $r } return 0 }
print f({m => 1, n => 5}), f({}), "\n";
print eval { f({m => 1}) } // $@;
P

round_trips(<<'P', 'return E // die, in an arm');
sub f { my ($o) = @_; if ($o > 1) { return $o // die "x\n" } return 0 }
print f(2), f(0), "\n";
P

round_trips(<<'P', 'E || die with a message built from the arm, in an arm');
sub f { my ($v, $k) = @_; if ($k) { my $x = $v || die "empty $k\n"; return "<$x>" } return '-' }
print f(3, 'a'), f(0, ''), "\n";
print eval { f(0, 'b') } // $@;
P

round_trips(<<'P', 'E && die, in an arm');
sub f { my ($bad, $k) = @_; if ($k) { my $x = $bad && die "bad\n"; return "ok" . ($x // 'u') } return '-' }
print f(0, 1), f(1, 0), "\n";
print eval { f(1, 1) } // $@;
P

# THE SAME BRANCH IN A LOOP BODY carries E into the loop: E is the dead arm's
# value too, so the merge keeps E's stamp and the accumulator stays stamped.
round_trips(<<'P', 'E // die in a loop body, feeding an accumulator');
my %h = (a => 1, c => 2); my $s = 0;
for my $k (qw(a c)) { my $v = $h{$k} // die "no $k\n"; $s += $v }
print "$s\n";
P

round_trips(<<'P', 'E || die in a loop body');
my %h = (a => 1, c => 2); my $s = 0;
for my $k (qw(a c)) { my $v = $h{$k} || die "no $k\n"; $s += $v }
print "$s\n";
P

done_testing;
