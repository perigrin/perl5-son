# ABOUTME: early returns merge two at a time, so an exit Phi can take another Phi; a list
# ABOUTME: under the inner one still makes the outer a list, read by the caller's context.

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

# chalk's CoreItemIndex::advance: `return $m{$id} if ...; return unless ...;
# return $n`. The bare return and `return $n` merge under their If first, and
# that merge is one input of the outer exit Phi. The outer Phi was a scalar,
# so it took the inner list's count: perl 42,42,u,u,0, deparsed 1,42,0,1,1.
for my $src (
    q{my %m; my @info = (undef, {d => 1}, {d => 2});
      sub f { $_[0]{d} == 1 ? 42 : undef }
      sub adv { my $id = shift; return $m{$id} if exists $m{$id}; my $i = $info[$id];
                return unless defined $i; my $n = f($i); $m{$id} = $n if defined $n; return $n }
      my $a = adv(1); my $b = adv(1); my $c = adv(0); my $d = adv(2); my @e = adv(0);
      print join(",", map { $_ // 'u' } $a, $b, $c, $d, scalar(@e)), "\n";},
    q{sub g { my $x = shift; return 'a' if $x == 1; return if $x == 2; return (7, 8) if $x == 3; 'z' }
      my @a = g(1); my @b = g(2); my @c = g(3); my @d = g(4);
      my $e = g(1); my $f = g(2); my $h = g(3); my $i = g(4);
      print join("|", scalar(@a), scalar(@b), scalar(@c), scalar(@d), map { $_ // 'u' } $e, $f, $h, $i), "\n";},
) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    ok($data, "translates") or next;
    my $perl = SoN::Deparse->new->render($data);
    is(run_perl($perl), $want, "deparses to what perl prints: $want")
        or diag $perl;
}

done_testing;
