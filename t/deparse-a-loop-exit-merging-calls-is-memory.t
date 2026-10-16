# ABOUTME: An exit Phi over method calls read only by memory merges is memory, not a value:
# ABOUTME: bound as a variable, its seed was spelled above the loop, before the call it names.

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


# chalk's LR0DFA::_compute_prediction_closure: an inner while with two
# breaks, each after a method call, inside a `while (my $x = shift @q)`.
# The calls are memory versions, so the exit Phi over them is a memory
# merge that only the outer loop's memory Phi reads. Bound as a value its
# seed, a call from the body, was declared before the loop: `my $exit87 =
# $eff82` above `my $eff82`.
round_trips(<<'SRC', 'an inner loop leaving by two breaks after method calls');
use v5.42.0;
package O { sub new ($c, $v) { bless { v => $v }, $c } sub ok ($s) { $s->{v} > 0 } sub odd ($s) { $s->{v} % 2 } }
sub f { my @r; my @todo = @_; while (my $x = shift @todo) { my $i = 0; my @k; while ($i < @$x) { my $o = $x->[$i]; last unless $o->ok; if ($o->odd) { push @k, $i; $i++ } else { last } } push @r, "@k" } return join("|", @r) }
print f([map { O->new($_) } 1, 3, 2, 5], [map { O->new($_) } 0, 1], [map { O->new($_) } 7]), "\n";
SRC

done_testing;
