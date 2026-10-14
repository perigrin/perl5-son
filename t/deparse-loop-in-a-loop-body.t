# ABOUTME: A loop nested in a loop body round trips: the inner loop builds its own Loop on
# ABOUTME: the body's control. Shapes it cannot lower soundly refuse by name.

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


sub refuses ($src, $why, $name) {
    graph_of($src);
    like producer_stderr(), $why, "$name: refuses by name";
}

# NESTED LOOPS. Each shape is checked by running it, not by the graph's shape.
round_trips(<<'SRC', 'a while in a foreach');
my $s=0; for my $i (1..3) { my $j=0; while ($j < $i) { $s += $j; $j++ } } print "$s\n";
SRC
round_trips(<<'SRC', 'a while in a while');
my $s=0; my $i=0; while ($i < 3) { my $j=0; while ($j < 2) { $s++; $j++ } $i++ } print "$s\n";
SRC
round_trips(<<'SRC', 'a bare block in a foreach');
my $s=0; for my $i (1..3) { { $s += $i } } print "$s\n";
SRC
round_trips(<<'SRC', 'an inner while(1) left by last');
my $s=0; for my $i (1..3) { my $j=0; while (1) { last if $j >= $i; $s++; $j++ } } print "$s\n";
SRC
round_trips(<<'SRC', 'next OUTER from an inner while');
my $s=0; OUTER: for my $i (1..4) { my $j=0; while ($j < 3) { $j++; next OUTER if $i == 2; $s += $j } } print "$s\n";
SRC
round_trips(<<'SRC', 'an inner loop with a continue block');
my $s=0; for my $i (1..3) { my $j=0; while ($j < 2) { $s += 100 } continue { $j++; $s += 5 } } print "$s\n";
SRC
round_trips(<<'SRC', 'a return from an inner while');
sub f { my $n=0; for my $i (1..9) { my $j=0; while ($j < 3) { $n++; return $n if $n == 5; $j++ } } -1 } print f(), "\n";
SRC
round_trips(<<'SRC', 'a while over a match in a while');
my $s = "aXbXc"; my $n = 0; while ($s =~ /X/g) { my $p = pos($s); my $d = 0; while ($p < length $s) { $d++; $p++ } $n += $d } print "$n\n";
SRC

# THE OUTER SCOUT MUST SEE THROUGH AN INNER FOREACH. It dropped `$s`'s Phi,
# printing "25,26," where perl prints "15,16,25,26,".
round_trips(<<'SRC', 'a foreach over an array in a foreach over an array');
my $s=""; my @a=(1,2); my @b=(5,6); for my $x (@a) { for my $y (@b) { $s .= "$x$y," } } print "$s\n";
SRC

# A C-STYLE FOR'S INIT SCOPE ENDS IN AN unstack THAT IS NOT THE ITERATION END.
round_trips(<<'SRC', 'a C-style for in a foreach');
my $s=0; for my $i (1..3) { for (my $j=0; $j<$i; $j++) { $s += 10 } $s += 1 } print "$s\n";
SRC

# A GUARD ARM THAT STOPS SHORT OF THE JOIN IS NOT THE WHOLE ARM. These printed
# 0, 0 and 12: the rest of the arm vanished.
refuses(<<'SRC', qr/GAP: untranslatable op inside a guarded arm \(arm stopped at `enterloop`/, 'a bare block in an if arm in a loop body');
my $s=0; for my $i (1..3) { if ($i > 1) { { $s += 10 } } } print "$s\n";
SRC
refuses(<<'SRC', qr/GAP: untranslatable op inside a guarded arm \(arm stopped at `enterloop`/, 'a while in an if arm in a loop body');
my $s=0; for my $i (1..3) { if ($i > 1) { my $k=0; while ($k<2) { $s += 10; $k++ } } } print "$s\n";
SRC
refuses(<<'SRC', qr/GAP: untranslatable op inside a guarded arm \(arm stopped at `iter`/, 'a postfix while in a foreach');
my $s=0; for my $i (1..3) { my $j=0; $j++ while $j < $i; $s += $j } print "$s\n";
SRC

# A BARE BLOCK'S next/last/redo TARGET THE BLOCK, not the enclosing loop.
refuses(<<'SRC', qr/GAP: a bare block with a next\/last\/redo inside a loop body/, 'last in a bare block in a loop body');
my $s=0; for my $i (1..3) { { $s+=$i; last if $i==2; $s+=100 } } print "$s\n";
SRC

# CHALK'S SHAPE, reduced: EagerPinning::_pick_outer_return walks a chain in a
# while nested in a foreach, leaving by `last if`.
round_trips(<<'SRC', 'a chain walk with last-if guards in a foreach');
my @r = ([1,2,3],[4,5],[6]); my $best = 0; my $bl = -1; for my $r (@r) { my $len = 0; my $i = 0; my %seen; while ($i < @$r) { last if $seen{$r->[$i]}++; $len++; $i++ } if ($len > $bl) { $best = $r; $bl = $len } } print "$bl @$best\n";
SRC

done_testing;
