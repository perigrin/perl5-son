# ABOUTME: A `die` that is the last statement of a loop body is on the wire and dies:
# ABOUTME: the body walk stepped past it, so `for (1) { die }` ran on (audit 2026-11-22, risk 1).

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
    my @unwind = grep { $_->{op} eq 'Unwind' } map { $_->{nodes}->@* } values $data->{methods}->%*;
    ok scalar @unwind, "$name: the die is on the wire";
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) { my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s; fail "$name: renders"; diag $g; return }
    is run_perl($out), $want, $name or diag "--- emitted ---\n$out";
}

round_trips(q{for my $x (1) { die "m\n" } print "after\n";}, 'a foreach whose body is a die');
round_trips(q{my $i = 0; for my $x (1, 2) { $i++; die "m$i\n" } print "after\n";}, 'a die after a statement');
round_trips(q{eval { my $i = 0; while ($i < 3) { $i++; die "w$i\n" } }; print "[$@]\n";}, 'a while in an eval');
round_trips(q{sub t { for my $x (1) { die "t\n" } "end" } print eval { t() } // "died", "\n";}, 'in a sub, caught by its caller');
round_trips(q{eval { die "a\n" for 1; }; print "[$@]\n";}, 'a postfix-for die');

done_testing;
