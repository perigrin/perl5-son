# ABOUTME: A foreach over a literal list whose iterator is passed to a call binds the
# ABOUTME: iterator from the list's element -- a value, not a store into the list.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

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


# A DEMOTED ITERATOR'S BINDING is `Assign(PadAccess x, Subscript(list, i))` --
# the element is the VALUE. The renderer's target walk takes a Subscript for a
# target, so both inputs read as targets; position settles a scalar assign as
# [target, value], but the refusal of a store into an anonymous list ran
# first, and refused the value.
round_trips(<<'SRC', 'a literal list at file scope');
sub g { $_[0] } my $o = ""; for my $x (1, 2) { $o .= g($x) } print "$o\n";
SRC

round_trips(<<'SRC', 'a literal list in a sub');
sub g { $_[0] } sub f { my $o = ""; for my $x (1, 2, 3) { next unless g($x) > 1; $o .= $x } $o } print f(), "\n";
SRC

round_trips(<<'SRC', 'a qw list');
sub g { uc $_[0] } my $o = ""; for my $x (qw(a b)) { $o .= g($x) } print "$o\n";
SRC

done_testing;
