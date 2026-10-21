# ABOUTME: `\($c ? $v : ...)` takes a reference to $v itself, so $v lives in its
# ABOUTME: pad slot as `\$v` makes it, and a read or write through it reaches $v.

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

# A REFERENCE TO A TERNARY IS A REFERENCE TO WHAT ITS ARM YIELDS: the variable
# itself. Its arm spells the variable, but the reference was not counted as
# taking $v's address, so $v was never stored to its slot -- `v=` for `v=5`
# (chalk's LLVM::Context::_lower_constant, `${\(defined $val ? $val : 'undef')}`).
round_trips(q{package N { sub new { bless { v => $_[1] }, $_[0] } sub val { $_[0]{v} } } sub f { my ($n) = @_; my $v = $n->val; return "v=${\(defined $v ? $v : q{u})}" } print f(N->new(5)), f(N->new(undef)), "\n";},
    'a read through a reference to a ternary of a variable');
round_trips(q{sub f { my ($c) = @_; my $v = 7; my $r = \($c ? $v : 0); $$r = 9 if $c; return "$v" } print f(1), f(0), "\n";},
    'a write through a reference to a ternary of a variable');

done_testing;
