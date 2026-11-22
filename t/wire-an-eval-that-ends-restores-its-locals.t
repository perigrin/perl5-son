# ABOUTME: A `local` in an eval that ends without a die is put back at the eval's end, as on
# ABOUTME: its exceptional edges: it was restored only there (audit 2026-11-22, risk 2).

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

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src) or return fail "$name: translates";
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) { my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s; fail "$name: renders"; diag $g; return }
    is run_perl($out), $want, $name or diag "--- emitted ---\n$out";
}


round_trips(q{our $g=1; eval { local $g = 2; 1 }; print "$g\n";}, 'a void eval');
round_trips(q{our $g=1; my $r = eval { local $g = 2; 5 }; print "$g $r\n";}, 'an eval whose value is used');
round_trips(q{our $g=1; eval { local $g = 2; f() }; sub f { 1 } print "$g\n";}, 'an eval ending in a call');
round_trips(q{use feature 'try'; no warnings; our $g = 1; try { local $g = 2; } catch ($e) { } print "$g\n";}, 'a try');
round_trips(q{our $g=1; sub sh { print "$g\n" } eval { local $g = 2; sh(); 1 }; sh();}, 'read by a callee either side');
round_trips(q{$@ = "x"; eval { local $@ = "y"; 1 }; print "[$@]\n";}, 'local $@ in the eval, then cleared');

done_testing;
