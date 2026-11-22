# ABOUTME: A foreach's alias of $_ is a memory version: a store to $_ after it -- a callee's --
# ABOUTME: is a store to the element, and the verifier holds it to that (audit 2026-11-22, 5.1).

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use SoN::Deparse;
use SoN::Verify;

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

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src) or return fail "$name: translates";
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) { my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s; fail "$name: renders"; diag $g; return }
    is run_perl($out), $want, $name or diag "--- emitted ---\n$out";
}


for my $src ( q{my @l = (1,2); for (@l) { inner(); } sub inner { $_ = 9 } print "@l\n";},
              q{our @l = (1,2); for (@l) { inner(); } sub inner { $_ = 9 } print "@l\n";} ) {
    my $w = graph_of($src) or do { fail "a wire for $src"; next };
    my @a = grep { $_->{op} eq 'LocalAlias' } map { $_->{nodes}->@* } values $w->{methods}->%*;
    ok scalar(@a), "$src: an alias";
    is [ grep { !$_->{mem_out} } @a ], [], "$src: each a memory version";
    is [ map { "$_->{op}#$_->{node} $_->{rule}" } SoN::Verify::verify($w)->{violations}->@* ], [], "$src: verifies clean";
}

done_testing;
