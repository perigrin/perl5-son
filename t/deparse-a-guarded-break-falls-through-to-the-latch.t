# ABOUTME: An arm whose `last unless` guard falls through to the loop's latch pays the
# ABOUTME: latch's variables on that path, so the next pass sees what the arm computed.

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


# `if (C) { my $h = ...; last unless defined $h; $cur = $h; next }`: the
# break's rest arm reaches the latch by falling through, and the latch was
# excluded as a join because the break's `next` edge targets it too -- so the
# arm assigned nothing, the loop read the other arm's last values, and ran
# forever. Silent on base (a hang). chalk's EagerPinning::schedule walks a
# control chain so.
round_trips(<<'P', 'a guarded break, then a step and a next');
sub f {
    my ($n) = @_;
    my $c = 0;
    my $cur = $n;
    while (defined $cur) {
        if (ref $cur eq "ARRAY") {
            my $h = $cur->[0];
            last unless defined $h;
            $c += 10;
            $cur = $h;
            next;
        }
        $c++;
        $cur = $cur->{next};
    }
    return $c;
}
print f({next => [{next => undef}]}), f([undef]), f(undef), "\n";
P

done_testing;
