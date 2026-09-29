# ABOUTME: `last if C` as the first statement of a loop that already has a
# ABOUTME: condition is a break, not a second condition -- it no longer refuses.

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

# THE HOIST IS FOR A HEADLESS LOOP. `while (1) { last if C; ... }` has no
# condition, so the first guard IS the continuation and hoists. A loop with a
# condition already consumed refused the same guard -- "last inside a loop
# body already has a loop condition" -- when the mid-body break handler
# builds it correctly one statement later. Corpus 006.
round_trips(<<'SRC', 'a last at the head of a while with a condition');
my $n = $ENV{N} // 5;
my $i = 0;
while ($i < $n) { last if $i > 1; print "-w$i"; $i = $i + 1 }
print "\n";
SRC

# THE HEADLESS FORM MUST STILL HOIST.
round_trips(<<'SRC', 'a last at the head of while (1)');
my $i = 0;
while (1) { last if $i > 2; print "-$i"; $i = $i + 1 }
print "\n";
SRC

done_testing;
