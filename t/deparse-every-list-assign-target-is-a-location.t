# ABOUTME: Every target of a list assign is a location, not a read: the second
# ABOUTME: target gets no stale temporary read above the `my` that declares it.

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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK
//mr;
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
        my $g = $d->gap // '(no reason)'; $g =~ s/
.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---
$out--- got ---
$got--- want ---
$want";
}
round_trips(<<'SRC', 'the second target passed to a call');
sub sm { "<@_>" } sub g { $_[0] }
sub f { my ($l) = @_; my ($c, $i) = @{g($l)}; my $r = sm($c, $i); return "x$r" }
print f([1, 5]), "\n";
SRC

round_trips(<<'SRC', 'the third target, read after another call');
sub g { $_[0] } my $n = 0; sub bump { $n++ }
sub f { my ($a, $b, $c) = @{g($_[0])}; bump(); return "$a$b$c$n" }
print f([1, 2, 3]), "\n";
SRC

round_trips(<<'SRC', 'chalk DefinedOrFold::_fold, a guard on the second target');
package O { sub new { bless { i => $_[1] }, $_[0] } sub inputs { $_[0]{i} } }
sub sm { 0 }
sub f { my ($l) = @_; my ($c, $i) = ($l->inputs // [])->@*;
    return "u" unless $i->can("inputs") && $i->inputs eq "K";
    return "r" if sm($c, $i); return "x" }
print f(O->new([1, O->new("K")])), f(O->new([1, O->new("J")])), "\n";
SRC

done_testing;
