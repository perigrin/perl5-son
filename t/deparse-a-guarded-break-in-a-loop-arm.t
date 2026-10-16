# ABOUTME: A `last` or `next` under a further guard in a loop-body if arm keeps the
# ABOUTME: arm's own test, and the arm join is not taken for the loop's exit.

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


round_trips(<<'SRC', 'an arm whose body is `last unless D`, after an earlier break');
sub f { my $cur = shift; my $len = 0; while ($cur < 20) { $len++; last if $len > 9; if ($cur == 2) { last unless $len == 4; } $cur++; } return $len }
print f(1), f(4), "\n";
SRC

round_trips(<<'SRC', 'an arm whose body is `next unless D`, after an earlier break');
sub f { my $cur = shift; my $len = 0; while ($cur < 20) { $len++; last if $len > 9; if ($cur == 2) { next unless $len == 4; } $cur++; } return $len }
print f(1), f(4), "\n";
SRC

round_trips(<<'SRC', 'an arm that breaks unless a lookup is defined, then rebinds');
my %p = (1 => 2, 2 => 3, 3 => 0, 5 => 6); my %in = (4 => [5]);
sub f { my $cur = shift; my $len = 0; while ($cur) { $len++; last if $len > 9; my $next = $p{$cur};
  if (!defined $next) { my $ins = $in{$cur}; last unless defined $ins; $next = $ins->[0]; }
  $cur = $next; } return $len }
print f(1), f(4), "\n";
SRC

round_trips(<<'SRC', 'an arm with a nested break whose sibling reaches the exit by a later break');
sub f { my $cur = shift; my $len = 0; while ($cur) { $len++; my $next = $cur > 1 ? $cur - 1 : undef; if (!defined $next) { last unless $len; $next = 0; } $cur = $next; last if $len > 50; } return $len }
print f(5), f(2), "\n";
SRC

done_testing;
