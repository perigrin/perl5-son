# ABOUTME: A loop body that ends in a bare `last` goes round only along its `next` arms:
# ABOUTME: the last is an edge to the exit, and the latch is what the nexts carry.

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


# chalk's EmitHelpers::_build_exists_delete_native walks a chain this way.
round_trips(q{my $c = \\\\\\3; my $n = 0; while (defined $c) { if (ref $c) { $c = $$c; $n++; next } last } print "$n $c\n";},
    'an if arm that nexts, then a bare last');
round_trips(q{my @r; my $i = 0; while ($i < 9) { $i++; if ($i < 3) { push @r, $i; next } if ($i == 5) { push @r, "f"; next } push @r, "e$i"; last } print "@r\n";},
    'two next arms, then an effect and a bare last');
round_trips(q{my $s = 0; my $i = 0; while ($i < 9) { $i++; if ($i < 4) { $s += $i; next } last } continue { $s += 10 } print "$s $i\n";},
    'the next arms run the continue block; the last does not');
round_trips(q{my $s = ""; for my $x (qw(a b c d)) { if ($x ne "c") { $s .= $x; next } last } print "$s\n";},
    'a foreach body ending in last');

# Every path leaves: there is no back edge to build, and that stays refused.
{
    graph_of(q{my $s = 0; for my $i (1..3) { $s += $i; last } print "$s\n";});
    like producer_stderr(), qr/GAP: loop control \(last\) inside a loop body not yet lowered/,
        'a body whose only path is a last refuses by name';
}

done_testing;
