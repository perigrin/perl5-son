# ABOUTME: A lexical sub (`my sub f`) is lifted like an anonymous sub and called by its
# ABOUTME: body's name; its padcv once pushed nothing, and `f($ctx)` became `$ctx->()`.

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


round_trips('use v5.36; my sub f ($x) { $x + 1 } print f(41), "\n";', 'a lexical sub called at top level');
round_trips('use v5.36; my sub f ($x) { $x + 1 } sub g { f(1) + f(2) } print g(), "\n";', 'a lexical sub called from a named sub');
round_trips('use v5.36; use experimental "class"; class C { my sub h ($x) { $x * 2 } method m ($y) { h($y) } } print C->new->m(21), "\n";',
    'a lexical sub called from a method, as chalk TypeInferenceActions does');
# A LEXICAL SUB CLOSING OVER A LEXICAL is refused by the renderer: its
# cell is made at the call, not where the sub is introduced.
{
    my $d = SoN::Deparse->new;
    my $g = graph_of('use v5.36; my $n = 10; my sub add ($x) { $x + $n } print add(1), add(2), "\n";');
    ok $g, 'a lexical sub closing over a lexical: translates';
    is $d->render($g), undef, '... and does not render';
    like $d->gap // '', qr/CellParam whose cell cannot be resolved/, '... naming the unresolved cell';
}
round_trips('use v5.36; my sub f ($x) { $x * 3 } my $r = \&f; print $r->(2), "\n";', 'a reference to a lexical sub');
round_trips('use v5.36; my sub f ($x) { [$x, $x] } print scalar(@{ f(4) }), "\n";', 'a lexical sub returning a reference');

done_testing;
