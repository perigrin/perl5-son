# ABOUTME: `redo if C` as the first statement of a loop body, with a test that
# ABOUTME: changes nothing, restarts on the same state: it is `while (C) {}`.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

# A TIME LIMIT, as for every loop test: a wrong lowering can spin.
sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; diag producer_stderr(); return;
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

# A REDO IS AN EDGE BACK TO THE BODY'S ENTRY -- a loop of its own. When it
# heads the body and its test has no effect, nothing differs between one
# restart and the next, so the loop it makes is exactly `while (C) {}`: it
# spins when C holds and falls through when it does not. Corpus 116 and 006,
# both of which run it with C false.
round_trips(<<'SRC', 'redo if C heading a foreach body, C false');
my $r = $ENV{R} // 0;
my @l = ($ENV{A} // "a", "b", "c", "d");
foreach my $x (@l) {
    redo if $r;
    next if $x eq "b";
    last if $x eq "d";
    print $x;
}
print "\n";
SRC

round_trips(<<'SRC', 'redo if C heading a while body');
my $i = 0;
my $r = $ENV{R} // 0;
while ($i < 3) {
    redo if $r > 5;
    print $i;
    $i = $i + 1;
}
print "\n";
SRC

# THE SPIN IS REAL: with C true, perl never leaves. The emitted program must
# not either, so both are cut off by the same time limit.
round_trips(<<'SRC', 'redo if C with C true spins, as perl does');
my $r = 1;
for my $x (1..2) { redo if $r; print $x }
print "unreached\n";
SRC

# ANYTHING ELSE STILL REFUSES, by name: a redo after a statement restarts on
# state the body has changed, which is a loop this does not build.
{
    my $data = graph_of(<<'SRC');
my $n = 0;
for my $x (1..2) { $n++; redo if $n == 1; print $x }
SRC
    ok !($data && $data->{methods}{'main::__PROGRAM__'}),
        'a redo after a statement does not translate';
    like producer_stderr(), qr/redo\) after the body has done something/,
        "... and names why";
}

done_testing;
