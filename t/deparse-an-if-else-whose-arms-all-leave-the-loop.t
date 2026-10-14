# ABOUTME: An if/else in a loop body whose arms all leave -- by next, last or return --
# ABOUTME: goes round along its next arms alone; with no next arm it refuses by name.

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


round_trips(q{my $s=""; for my $i (1..5) { if ($i % 2) { $s .= "o"; next } else { $s .= "e"; last } } print "$s\n";},
    'one arm nexts, the other lasts');
round_trips(q{my $s=""; for my $i (1..5) { if ($i < 3) { $s .= "a"; next } else { $s .= "b"; next } } print "$s\n";},
    'both arms next');
round_trips(q{sub f { my $s=""; for my $i (1..5) { if ($i < 3) { $s .= "a"; next } else { return "$s!" } } $s } print f(), "\n";},
    'one arm nexts, the other returns');
round_trips(q{my $s=""; my $i=0; while ($i < 5) { $i++; if ($i % 2) { $s .= "o"; next } else { $s .= "e"; next } } continue { $s .= "," } print "$s\n";},
    'both arms next through a continue block');

# No arm goes round: there is no back edge.
{
    graph_of(q{sub f { for my $i (1..3) { if ($i==2) { print "a"; return 1 } else { print "b"; last } } 9 } print f(), "\n";});
    like producer_stderr(), qr/GAP: an if\/else in a loop body whose arms all leave, none by `next`, is not yet lowered/,
        'arms that return and last refuse by name';
}
# Nested in an arm, an outer arm reading the signal would record its edges twice.
{
    graph_of(q{my $s=""; for my $i (1..5) { if ($i == 1) { $s.="x" } elsif ($i % 2) { $s .= "o"; next } else { $s .= "e"; last } $s.="-" } print "$s\n";});
    like producer_stderr(), qr/GAP: an if\/else whose arms all leave the loop, nested in an arm, is not yet lowered/,
        'an elsif chain whose inner arms all leave refuses by name';
}

done_testing;
