# ABOUTME: a statement modifier at the top of a `while (1)` body is a guard in the
# ABOUTME: body, not the loop's condition: the loop runs until its `last`.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; return;
    }
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

# `while (1)` HAS NO CONDITION -- perl folds it away -- so the first `and`
# the body walk meets is a statement's guard. Taken for the loop's test,
# `$s .= "a" if $x < 2` ended the loop at $x == 2 and ran the `.=` every
# pass: perl's "5 aa" came back "2 aa".
#
# THE SHAPE IS THE CHECK: the Loop has no Projs (no header test), and the
# guard's comparison is an If's condition, not pinned to the Loop. The
# deparser gives perl's answer or refuses by name.
sub headless_with_guard ($src, $cmp, $name) {
    my $g = graph_of($src)->{methods}{'main::__PROGRAM__'};
    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my ($loop) = grep { $_->{op} eq 'Loop' } $g->{nodes}->@*;
    ok(!grep({ $_->{op} eq 'Proj' && $_->{inputs}[0] == $loop->{id} } $g->{nodes}->@*),
       "$name: the loop has no header test");
    my ($c) = grep { $_->{op} eq $cmp } $g->{nodes}->@*;
    ok(!defined $c->{control_in}, "$name: the guard is not pinned to the loop");
    ok(scalar(grep { $_->{op} eq 'If' && grep { $_ == $c->{id} } $_->{inputs}->@* } $g->{nodes}->@*),
       "$name: the guard is an If's condition");
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src));
    if (!defined $out) { like($d->gap, qr/\AGAP:/, "$name: refused by name") }
    else { is(run_perl($out), run_perl($src), "$name: perl's answer") }
}
headless_with_guard(<<'SRC', 'NumLt', 'a guarded statement first in the body');
my $x = 0; my $s = "";
while (1) { $s .= "a" if $x < 2; $x = $x + 1; last if $s eq "aa" && $x > 4 }
print "$x $s\n";
SRC
headless_with_guard(<<'SRC', 'NumGt', 'an unless-guarded statement first in the body');
my $x = 0; my $s = "";
while (1) { $s .= "b" unless $x > 1; $x = $x + 1; last if $x == 4 }
print "$x $s\n";
SRC
# A written condition is still the condition.
round_trips(<<'SRC', 'while (C) keeps its condition');
my $x = 0; my $s = "";
while ($x < 3) { $s .= "c" if $x; $x = $x + 1 }
print "$x $s\n";
SRC

done_testing;
