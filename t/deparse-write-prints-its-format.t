# ABOUTME: `write` runs its format and prints the accumulated picture to the
# ABOUTME: handle; calling the format body alone only fills $^A.

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

# THE FORMAT BODY IS formline, WHICH ONLY APPENDS TO $^A. `write` is what
# prints the accumulator to the handle and empties it; the emission called
# the body and stopped there, so nothing reached stdout. Corpus 102, 103.
round_trips(<<'SRC', 'a fixed format line');
format STDOUT =
a fixed report line
.
write;
print "after write\n";
SRC

round_trips(<<'SRC', 'a format with fields');
our ($name, $qty);
format STDOUT =
@<<<<<<< @>>>
$name,   $qty
.
$name = "widget";
$qty = 7;
write;
$name = "gear";
$qty = 12;
write;
print "after write\n";
SRC

done_testing;
