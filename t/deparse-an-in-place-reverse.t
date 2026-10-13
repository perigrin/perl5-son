# ABOUTME: `@b = reverse @b` -- which perl compiles to an in-place reverse with no list
# ABOUTME: assign -- rebinds the array to its reversed contents; in a loop it refuses.

use v5.42.0;
use Test2::V0;
use JSON::PP;
# ABOUTME: A whole-aggregate assignment in a branch arm, in a loop or straight-line, round
# ABOUTME: trips: each assigned version is its own variable and an array merge stays an array.

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


round_trips('my @b = (1, 2); @b = reverse @b; print "@b\n";', 'an in-place reverse');
round_trips('my $c = 1; my @b = $c ? (1, 2) : (); @b = reverse @b; print "@b\n";', 'an in-place reverse of a ternary-filled array');
round_trips('sub f { my @b = @_; @b = reverse @b; return "@b" } print f(1,2,3), "\n";', 'an in-place reverse in a sub');
round_trips('my @b = (1,2); @b = reverse @b; push @b, 9; print "@b ", scalar(@b), "\n";', 'an in-place reverse, then a push');
round_trips('my @t; my $i = 0; while (@t = $i < 2 ? (1) : ()) { $i++ } print "$i\n";', 'a ternary list assigned in a loop condition');

graph_of('my @b = (1,2,3); for (1..2) { @b = reverse @b; print "@b;" } print "\n";');
like producer_stderr(), qr/in-place reverse inside a loop body is not yet lowered/,
    'an in-place reverse in a loop refuses';
graph_of('our @g = (1,2); @g = reverse @g; print "@g\n";');
like producer_stderr(), qr/in-place reverse of something other than a lexical array/,
    'an in-place reverse of a package array refuses';

done_testing;
