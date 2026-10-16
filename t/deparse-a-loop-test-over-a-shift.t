# ABOUTME: A while whose test reads a per-pass effect through a value -- `while (my $n =
# ABOUTME: shift @q)` -- runs the effect at the top of each pass and tests what it read.

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


# The shift and the test are both pinned on the Loop, and the test reads the
# shift through an unpinned Not: Not(Not(shift)). Counting only direct inputs
# left both unconsumed, and the deparser refused.
round_trips(<<'P', 'a while over a shift');
sub f { my @q = @_; my $s = 0; while (my $n = shift @q) { $s += $n; } return $s }
print f(1), f(2, 2), f(9, 0, 4), f(), "\n";
P

round_trips(<<'P', 'a while over a shift with a next');
sub f { my @q = @_; my $s = 0; while (my $n = shift @q) { next if $n == 3; $s += $n; } return $s }
print f(1, 3, 4), f(2, 2), f(9), "\n";
P

# The returned `$n` is the shift, and the `$seen{$n}++` store makes the shift a
# memory version too: the function exit's Phi over it was skipped as memory,
# and the Return read a Phi nothing had bound.
round_trips(<<'P', 'a work queue that grows and returns from inside');
sub f {
    my %seen;
    my @q = @_;
    while (my $n = shift @q) {
        next if $seen{$n}++;
        return $n if $n > 5;
        push @q, $n + 2 if $n < 4;
    }
    return 0;
}
print f(1), f(2, 2), f(9), f(3, 1), "\n";
P

done_testing;
