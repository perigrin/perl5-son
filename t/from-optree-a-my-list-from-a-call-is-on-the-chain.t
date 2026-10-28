# ABOUTME: `my (...) = f()` -- a list assign whose value has no positions -- is
# ABOUTME: on the control chain, where its targets are bound, ahead of their reads.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# The list assign of a `my` from a call floated: nothing consumed it and it had
# no control input, so a consumer walking the chain never reached it, and the
# targets' reads (their own PadAccess nodes) had no value. A call's effects
# also fix its place: `my ($s) = f(); print "x"` prints f's output first.
for my $case (
    [ q{sub f { (1, 2) } my ($s, $m) = f(); print "$s $m\n";}, 'main::__PROGRAM__', 'a call' ],
    [ q{my ($s, $m, $h) = localtime(3725); print "$s $m $h\n";}, 'main::__PROGRAM__', 'a list builtin' ],
    [ q{sub f { (1, 2) } sub g { my ($s, $m) = f(); "$s$m" } print g(), "\n";}, 'main::g', 'in a sub' ],
) {
    my ($src, $graph, $name) = @$case;
    my $data = graph_of($src);
    my $nodes = $data->{methods}{$graph}{nodes} // [];
    my ($assign) = grep { $_->{op} eq 'Assign' && ( $_->{fields}{targets} // 0 ) > 1 } @$nodes;
    ok $assign, "$name: a list assign" or next;
    ok defined( $assign->{control_in} // $assign->{control} ), "$name: it is on the control chain";
}

# AND THE MEMORY VERSION A LATER READ TAKES: a floating read of a target (a
# join over `($s) x $n`) was placed by its memory input, the call, ahead of
# the assignment that binds $s.
{
    my $data = graph_of(q{sub q2 { (3, "a") } my ($n, $s) = q2(); my @r = ($s) x $n; print "@r\n";});
    my $nodes = $data->{methods}{'main::__PROGRAM__'}{nodes} // [];
    my ($assign) = grep { $_->{op} eq 'Assign' && ( $_->{fields}{targets} // 0 ) > 1 } @$nodes;
    my ($join)   = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'join' } @$nodes;
    ok $assign && $join && $join->{inputs}[-1] == $assign->{id}, 'a later read takes the assignment as its memory';
}

done_testing;
