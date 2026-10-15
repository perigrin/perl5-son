# ABOUTME: A loop with two or more breaks leaves each with its own values: the exit Phi has
# ABOUTME: an input per Region predecessor, and each `last` pays the one its arm reaches.

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
