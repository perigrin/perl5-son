# ABOUTME: `goto $t` with a string operand is an edge set over the labels in
# ABOUTME: scope, selected by the runtime value; a label behind it is a loop.

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

# the program's stdout and how it ended, with stderr dropped: perl's message
# names the file it ran, which differs between the two programs.
sub outcome ($src) {
    my $f = "$dir/o." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); my $st = $? >> 8;
    unlink $f; return "$out|exit=$st";
}

# THE LABELS ARE IN THE OPTREE, so the set a string can select is known here;
# only the choice is made at run time. Corpus 117: SKIP lies behind the goto,
# TAIL ahead of it.
round_trips(<<'SRC', 'corpus 117: a forward goto, then a computed one');
my $c = $ENV{X} // 0;
my $t = $ENV{T} // "TAIL";
print "a";
goto SKIP unless $c;
print "b";
SKIP:
print "c";
goto $t;
print "d";
TAIL:
print "e\n";
SRC

round_trips(<<'SRC', 'a computed goto choosing between two labels ahead');
my $t = $ENV{T} // "B";
goto $t;
print "skipped";
A:
print "x";
B:
print "y\n";
SRC

# A NAME THAT IS NO LABEL: perl dies "Can't find label". The emission must
# end the same way, not fall through to the next statement.
{
    my $src = <<'SRC';
my $t = $ENV{T} // "NOPE";
print "a";
goto $t;
print "b";
L:
print "c\n";
SRC
    my $data = graph_of($src);
    my $out  = $data && SoN::Deparse->new->render($data);
    ok defined $out, 'a computed goto to no label renders' or diag producer_stderr();
    is outcome($out // ''), outcome($src), '... and dies where perl does';
}

# A LABEL BEHIND THE GOTO THAT A VALUE CROSSES -- `$i` changes between the
# label and the jump -- needs the loop's Phis, which this does not build.
{
    my $data = graph_of(<<'SRC');
my $i = 0;
my $t = $ENV{T} // "OUT";
TOP:
$i = $i + 1;
goto $t;
OUT:
print "$i\n";
SRC
    ok !($data && $data->{methods}{'main::__PROGRAM__'}),
        'a backward label with a carried value does not translate';
    like producer_stderr(), qr/computed goto.*carries/,
        '... and says why';
}

done_testing;
