# ABOUTME: A call into a package this program never defines reaches a sub
# ABOUTME: another module provides, like an import; it is rendered, not refused.

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

# A PACKAGE THIS FILE NEVER DEFINES is another module's: chalk's LLVM.pm calls
# Chalk::Target::LLVM::Context::_slot_idx, and Context calls back into LLVM,
# each loaded at run time. Refused as "a call into nothing", each module
# refused for the other's sake. Here the string eval is the other module.
round_trips(<<'SRC', 'a call into a package defined at run time elsewhere');
eval 'package Other; sub g { "g$_[0]" } 1' or die;
sub f { return Other::g($_[0]) }
print f(2), "\n";
SRC

# A SUB OF A PACKAGE THIS FILE DOES DEFINE, absent from the graph, is still
# one the producer dropped, and refused.
{
    my $src = q{package P; sub ok { 1 } package main; print P::nope(), "\n";};
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {});
    ok !defined $out, 'a missing sub of a package this file defines: refused';
    like $d->gap // '', qr/not in the graph/, '...naming why';
}

done_testing;
