# ABOUTME: `goto LABEL` to a label later in the same statement sequence is a
# ABOUTME: forward control edge: what it skips builds nothing, and it joins there.

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

# THE LABEL IS ON THE OP AND ON ITS TARGET'S nextstate, both visible here, so
# a forward jump is a control edge to a join at the label -- no loop, and no
# `goto` in the emission: the skipped statements simply never ran. Corpus 006
# (`goto DONE; print "-skipped"; DONE:`) and 117's `goto SKIP unless $c`.
round_trips(<<'SRC', 'an unconditional forward goto skips what lies between');
print "a";
goto DONE;
print "-skipped";
DONE:
print "\n";
SRC

round_trips(<<'SRC', 'a conditional forward goto, taken');
my $c = $ENV{X} // 0;
print "a";
goto SKIP unless $c;
print "b";
SKIP:
print "c\n";
SRC

round_trips(<<'SRC', 'a conditional forward goto, not taken');
my $c = $ENV{X} // 1;
print "a";
goto SKIP unless $c;
print "b";
SKIP:
print "c\n";
SRC

# A VALUE MERGES AT THE LABEL: `$x` is 1 along the jump and 2 along the
# fall-through, so the join is a Phi like any if's.
round_trips(<<'SRC', 'a binding the jump skips merges at the label');
my $c = $ENV{X} // 0;
my $x = 1;
goto L if !$c;
$x = 2;
L:
print "$x\n";
SRC

# A BACKWARD LABEL IS A LOOP, which this does not build: refused by name.
{
    my $data = graph_of(<<'SRC');
my $i = 0;
AGAIN:
$i = $i + 1;
goto AGAIN if $i < 3;
print "$i\n";
SRC
    ok !($data && $data->{methods}{'main::__PROGRAM__'}),
        'a backward goto does not translate';
    like producer_stderr(), qr/`goto AGAIN` whose label is not ahead/,
        '... and says why';
}

done_testing;
