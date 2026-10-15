# ABOUTME: An if/unless arm whose nested guard returns joins its sibling at the nearest
# ABOUTME: merge, not at the function's exit that a later return in the body also reaches.

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


# `if (!$o) { return "p" if $s }` beside a later `return "e" if $o > 5`:
# the arm's fall-through meets the true arm before the second test, but the
# guarded return meets the second test's return first in a breadth-first
# walk -- taken for the join, the rest of the body ran in both arms and the
# loop returned after one pass. Silent on base.
round_trips(<<'P', 'a negated arm with a guarded return, in a loop');
sub f {
    my $s = shift;
    for my $o (@_) {
        if (!$o) { return "p" if $s; }
        return "e" if $o > 5;
    }
    return "z";
}
print f(1, 1), f(1, 3, 0), f(0, 1, 7), f(1), "\n";
P

round_trips(<<'P', 'an unless-defined arm with a guarded return and a next');
sub f {
    my $same;
    my $seen = 0;
    for my $o (@_) {
        if (!defined $o) { return "p" if $seen; next; }
        if (!$seen) { $same = $o; $seen = 1; }
        elsif ($same ne $o) { return "p"; }
    }
    return $same // "p";
}
print f(1, 1), f(1, 2), f(undef, 3), f(3, undef), f(), "\n";
P

round_trips(<<'P', 'the same arm outside a loop');
sub f {
    my ($o, $s) = @_;
    if (!$o) { return "p" if $s; }
    return "e" if $o > 5;
    return "z";
}
print f(0, 1), f(0, 0), f(7, 0), f(1, 1), "\n";
P

done_testing;
