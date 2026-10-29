# ABOUTME: a call (or match, short-circuit, merge) among several list-assign values yields
# ABOUTME: any number of elements, so no target is bound to it by position.

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

# `my ($a, $b, $c) = (two(), 5)` bound $a to the Call and $b to 5: perl
# 1 2 5, emitted "2 5" and undef. chalk's Context.pm, `my ($p, $q, $r) =
# ($self->_fresh, $self->_fresh, $self->_fresh)`, spelled each name as the
# call's array -- in a string, its count -- and lli read `%Str 1`.
for my $src (
    q{sub two { (1, 2) } sub go { my ($a, $b, $c) = (two(), 5); print "$a $b $c\n" } go();},
    q{sub two { (1, 2) } sub go { my ($a, $b) = (5, two()); print "$a $b\n" } go();},
    q{my $n = 0; sub fresh { $n++; "%t$n" }
      sub go { my ($a, $b, $c) = (fresh(), fresh(), fresh()); print "  $a = x\n  $b = $a\n"; return $c }
      print go(), "\n";},
    # A merge is unsized only when what it merges is: an arm that is a call.
    q{sub two { (1, 2) } sub go { my ($a, $b) = ($_[0] ? two() : 3, 9); print "$a $b\n" } go(1); go(0);},
) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    ok($data, "translates") or next;
    my $d    = SoN::Deparse->new;
    my $perl = $d->render($data);
    # Refused by name is acceptable; a wrong answer is not.
    if (!defined $perl) { like($d->gap, qr/GAP/, "refused by name: $src"); next }
    is(run_perl($perl), $want, "deparses to what perl prints: $want")
        or diag $perl;
}

done_testing;
