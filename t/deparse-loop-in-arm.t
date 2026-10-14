# ABOUTME: A while/for loop, a bare block, or a runtime range inside an if/else arm
# ABOUTME: round trips: the arm walk dispatches them as the main walk does.

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


round_trips(<<'P', 'a while loop in an if arm');
sub f { my ($v) = @_; if ($v) { my $n = 0; while ($n < $v) { $n++ } print "$n\n" } return 0 }
f(3); f(0); f(1);
P

round_trips(<<'P', 'a while loop in an else arm, beside a store in the then arm');
my $c = shift // 1; my $n = 0;
if (!$c) { $n = 9 } else { while ($n < 3) { $n++ } }
print "$n\n";
P

round_trips(<<'P', 'a C-style for in an arm');
sub f { my ($v) = @_; my $s = 0; if ($v) { for (my $i = 0; $i < $v; $i++) { $s += $i } } return $s }
print f(4), " ", f(0), "\n";
P

round_trips(<<'P', 'a bare block in an arm');
sub f { my ($v) = @_; if ($v) { { print "in\n" } } print "out\n" }
f(1); f(0);
P

round_trips(<<'P', 'a while over a //gc match in an arm');
sub f { my ($v) = @_; my @p; if ($v) { my $r = $v; while ($r =~ /\G(.*?)\$(\w+)/gcs) { push @p, "$1|$2" } push @p, substr($r, pos($r) // 0) } return join(",", @p) }
print f('a$x b$y c'), "\n", f(''), "\n";
P

round_trips(<<'P', 'a while loop that returns, in an arm');
sub f { my ($v) = @_; if ($v) { my $n = 0; while ($n < 10) { return $n if $n * $n > $v; $n++ } } return -1 }
print f(10), " ", f(0), " ", f(200), "\n";
P

round_trips(<<'P', 'a runtime range under grep in an arm');
sub f { my ($k, @in) = @_; if ($k) { for my $i (grep { $_ % 2 == 0 } 0 .. $#in) { return $in[$i + 1] if $in[$i] eq $k } return 'none' } return 'nokey' }
print f('b', a => 1, b => 2), " ", f('z', a => 1), " ", f(''), "\n";
P

round_trips(<<'P', 'a runtime range assigned in an arm');
my $c = shift // 1; my $n = 3; my @x = (9);
if ($c) { @x = (1 .. $n) }
print "@x\n";
P

# A SCALAR `..` IN AN ARM IS THE FLIP-FLOP, desugared as it is outside one.
round_trips(<<'P', 'a flip-flop in an arm');
my $c = 1;
for my $l (1 .. 6) { if ($c) { print $l if ($l == 2) .. ($l == 4) } }
print "\n";
P

# ...and inside a sub its state outlives the call, which keeps its refusal.
graph_of(<<'P');
sub f { my ($c, $l) = @_; if ($c) { return 1 if ($l == 2) .. ($l == 4) } return 0 }
print map { f(1, $_) } 1 .. 6;
P
like producer_stderr(), qr/a flip-flop inside a sub is not yet lowered/,
    'a flip-flop in an arm of a sub refuses by name';

done_testing;
