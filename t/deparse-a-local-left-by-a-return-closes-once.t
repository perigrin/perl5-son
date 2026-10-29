# ABOUTME: a `local` element's block closes once: a `return` puts the element back by
# ABOUTME: itself in perl, so the restore on its path spells no `}` of its own.

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
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# Each restores on two paths: the return's and the fall-through end's. Every
# ElemRestore spelled `}`, so the block opened once and closed twice (chalk's
# Context.pm: "syntax error near } else").
for my $src (
    q{my %h = (a => 1); sub f { local $h{a} = 2; unless ($_[0]) { return $h{a} } $h{a} + 10 } print f(0), f(1), $h{a}, "\n";},
    q{my %h = (a => 1); sub f { local $h{a} = 2; if ($_[0]) { return 7 } $h{a} } print f(1), f(0), $h{a}, "\n";},
    q{my %h = (a => 1); sub f { local $h{a} = 2; for my $i (1 .. 3) { return $i if $i == 2 } 0 } print f(), $h{a}, "\n";},
) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    ok($data, "translates: $src") or next;
    my $perl = SoN::Deparse->new->render($data);
    is(run_perl($perl), $want, "deparses to what perl prints: $src")
        or diag $perl;
}

done_testing;
