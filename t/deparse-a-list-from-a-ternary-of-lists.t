# ABOUTME: A list assign from a ternary whose arms are a list call and `()` gets the
# ABOUTME: call's elements or none -- assigned after the branch, not declared empty above it.

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


# TWO DEFECTS, ONE STATEMENT. `()` in an arm was built as undef -- one
# element -- and the array that holds the merge was declared at the top of
# the sub and never assigned: the deferral that places a binding after the
# Phi it reads knew only a loop's Phi. Both paths gave 0 where perl gives 2
# and 0. chalk's Schedule::Elaborate::_elaborate_if is
# `my @then_chain = defined $proj0 ? _collect_branch_chain($proj0) : ();`,
# and every if/else merge lost its phi.
round_trips(<<'SRC', 'a list call or the empty list');
sub two { return (1, 2) }
sub f { my ($p) = @_; my @c = defined $p ? two() : (); return scalar(@c) }
print f(1), f(undef), "\n";
SRC

round_trips(<<'SRC', 'the empty list on the true arm');
sub three { return (7, 8, 9) }
sub f { my ($p) = @_; my @c = $p ? () : three(); return "@c|" . scalar(@c) }
print f(1), " ", f(0), "\n";
SRC

round_trips(<<'SRC', 'a hash from a ternary');
sub pairs { return (a => 1, b => 2) }
sub f { my ($p) = @_; my %h = $p ? pairs() : (); return join ",", map { "$_=$h{$_}" } sort keys %h }
print f(1), "|", f(0), "\n";
SRC

done_testing;
