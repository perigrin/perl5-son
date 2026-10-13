# ABOUTME: A loop-carried slot assigned from shift or pop round trips: the call is a
# ABOUTME: memory version too, but a header Phi read as a value still gets its variable.

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


# A CALL IS BOTH A VALUE AND A MEMORY VERSION. `shift` carries memory, so its
# loop Phi asks _is_memory yes -- but the slot is read as a value after the
# loop, and the header must still declare and seed it.
round_trips(<<'SRC', 'a loop-carried shift');
sub f { my $x = 0; my $n = 2; while ($n > 0) { $x = shift; $n = $n - 1 } $x }
print f(10,20), "\n";
SRC

round_trips(<<'SRC', 'a loop-carried pop');
sub f { my $x = $_[0]; my $n = 2; while ($n > 0) { $x = pop; $n = $n - 1 } $x }
print f(10,20,30), "\n";
SRC

done_testing;
