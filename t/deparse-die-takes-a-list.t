# ABOUTME: `die LIST` joins every operand into the message; the Unwind carries
# ABOUTME: them all, and the emission must pass them all.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>$dir/err);
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

# THE WIRE HAD BOTH OPERANDS -- Unwind in=[7, 8] -- and the deparser spelled
# only the first, so `die $g, "b\n"` died with `a\n` alone. Corpus 056;
# `die($g), "b\n"` is the control, where the parens make "b\n" not die's.
round_trips(<<'SRC', 'die with a list, and with a parenthesised operand');
my $g = $ENV{X} // "a\n";
eval { die $g, "b\n" };
my $wide = $@;
eval { die($g), "b\n" };
print "wide=", $wide, "narrow=", $@;
SRC

# A READ OF $@ INSIDE A TERNARY ARM IS NOT PINNED. The arm is walked on a
# snapshot and the select merges no control, so a pinned read forked the
# chain -- "a control node with 2 successors", perl's comp/package.t.
round_trips(<<'SRC', 'a $@ read in a ternary arm');
eval { die "boom\n" };
print $@ =~ /^boom/ ? "ok\n" : "not ok '$@'\n";
SRC

done_testing;
