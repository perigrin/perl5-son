# ABOUTME: A loop that leaves by more than one `last` keeps each exit value apart: the
# ABOUTME: exit Phi has one input per exit, and each break assigns only its own.

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


# The emission must also be QUIET: a second `my @e` in one scope is a "masks
# earlier declaration" warning, and the masked variable is the defect.
sub emits_quietly ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}


round_trips(<<'SRC', 'a counted foreach with two breaks, each after its own update');
my $n = 0; foreach my $i (1..9) { $n++; last if $i == 3; $n += 10; last if $i == 7 } print "$n\n";
SRC

round_trips(<<'SRC', 'a foreach over a list with two breaks');
my $n = 0; for my $x (@ARGV, 1..9) { $n++; last if $x == 3; $n += 10; last if $x == 7 } print "$n\n";
SRC

round_trips(<<'SRC', 'a flag written only on the break paths, two of them');
my $f = 0; foreach my $i (1..9) { if ($i == 3) { $f = 1; last } if ($i == 4) { $f = 2; last } } print "$f\n";
SRC

round_trips(<<'SRC', 'a while loop: the second break is taken, the first is not');
my $f = 0; my $i = 0; while ($i < 9) { $i++; if ($i == 30) { $f = 1; last } if ($i == 4) { $f = 2; last } } print "$f $i\n";
SRC

round_trips(<<'SRC', 'a while loop whose header test exits, with two breaks never taken');
sub f { my $cur = shift; my $len = 0; while ($cur) { $len++; last if $cur == 20 && $len <= 5; $cur = $cur - 1; last if $len > 9 } return $len }
print f(4), f(20), f(30), "\n";
SRC

round_trips(<<'SRC', 'a break inside an if arm and one after it: the shape of chalk _pick_outer_return');
sub f { my $cur = shift; my $len = 0; while ($cur) { $len++; my $next = $cur - 1; if ($cur == 2) { last unless $len > 5; $next = 9 } last if $len > 9; $cur = $next } return $len }
print f(4), f(1), "\n";
SRC

round_trips(<<'SRC', 'a break that pays two loop variables, each read by the other');
my ($a, $b) = (1, 2); my $i = 0; while ($i < 9) { $i++; ($a, $b) = ($b, $a + $b); last if $i == 3; ($a, $b) = ($b + 1, $a); last if $i == 5 } print "$a $b $i\n";
SRC

round_trips(<<'SRC', 'a `my` in the body is owed nothing at the exit');
sub f { my $cur = shift; my $len = 0; my %seen;
  while ($cur) {
    last if $seen{$cur}++;
    my $next = $cur > 1 ? $cur - 1 : undef;
    if (!defined $next) { last unless $len; $next = 0; }
    if ($next == 2) { $next = $len > 1 ? 1 : undef; }
  }
  return $len;
}
print f(5), f(2), "\n";
SRC

emits_quietly(<<'SRC', 'two payments on one break');
my $n = 0; my $m = 0; foreach my $i (1..9) { $n++; $m += $n; last if $i == 3; $n += 10; last if $i == 7 } print "$n $m\n";
SRC

# A Phi per break, chained [header, break] onto a three-predecessor Region,
# gave each break the other's values (eoe 3, abcd 5).
round_trips(q{my $s=""; my $i=0; while ($i < 9) { $i++; last if $i > 4; $s .= "e"; last if $i % 2 == 0; $s .= "o" } print "$s $i\n";},
    'two last-ifs in a while, a slot changed between them');
round_trips(q{my ($s,$n)=("",0); for my $x (qw(a b c d e)) { $n++; last if $x eq "d"; $s .= $x; last if $n > 2 } print "$s $n\n";},
    'two last-ifs in a foreach');
round_trips(q{my ($s,$n)=("",0); for my $x (qw(a b c d e)) { $n++; last if $x eq "d"; $s .= $x; last if $n > 7 } print "$s $n\n";},
    'two last-ifs in a foreach, the first one taken');
round_trips(q{my ($s,$f)=("",0); for my $x (1..9) { if ($x == 3) { $f = 1; last } if ($x == 7) { $f = 2; last } $s.=$x } print "$s $f\n";},
    'two if-blocks ending in last, each setting a flag');
round_trips(q{my $s=""; my $i=0; while ($i < 9) { $i++; last if $i > 4; if ($i % 2) { $s .= "o"; next } $s .= "e"; last } print "$s $i\n";},
    'a last-if, a next arm, and a bare last');

# `last unless C; ...; next`: the rest leaves by its next, the guard by
# its last, and the latch is the next (chalk's _fixup_ternary_assignment).
round_trips(q{my $s=""; my $i=0; while ($i < 9) { $i++; last unless $i < 5; $s .= $i; next } print "$s $i\n";},
    'last unless, then a rest ending in next');
round_trips(q{my $s=""; my $i=0; while ($i < 9) { $i++; last if $i > 4; $s .= $i; next } continue { $s .= "," } print "$s $i\n";},
    'the same through a continue block');
{
    graph_of(q{my $s=""; my $i=0; while ($i < 9) { $i++; last if $i > 4; $s .= $i; last } print "$s $i\n";});
    like producer_stderr(), qr/GAP: a `last if` whose rest of the body leaves, none by `next`, is not yet lowered/,
        'a last-if whose rest ends in last refuses by name';
}

done_testing;
