# ABOUTME: A block eval's (and a try's) join is a memory version: a caught die sets $@ with
# ABOUTME: no store on the chain, so a read after the eval must not share the version of one in it.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# Nested: the inner eval's message read, then the outer's. Both reads took
# the memory the inner body left -- one version, so a consumer merging nodes
# by their inputs made them one read, and printed "inner" for the outer.
for my $case (
    [ q{my $o = eval { my $i = eval { die "in\n" }; print "inner: $@"; die "out\n" }; print "outer: $@";}, 'nested evals' ],
    [ q{use v5.36; no warnings; use feature "try"; my $x = eval { die "a\n" }; print $@; try { die "b\n" } catch ($e) { print $e } print $@;}, 'an eval, then a try' ],
) {
    my ($src, $name) = @$case;
    my $data  = graph_of($src);
    my @nodes = $data->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    my %by_id = map { $_->{id} => $_ } @nodes;
    my @joins = grep { $_->{op} eq 'Region' && defined $_->{fields}{eval_id} } @nodes;
    ok scalar(@joins), "$name: the evals have their joins";
    for my $r (@joins) {
        ok( ( grep { $_->{op} eq 'Phi' && $_->{fields}{memory} && ( $_->{fields}{region} // -1 ) == $r->{id} } @nodes ),
            "$name: eval $r->{fields}{eval_id}'s join versions memory" );
    }
    my @reads = grep { $_->{op} eq 'EntryDef' && ( $_->{fields}{symbol} // '' ) eq '@' && defined $_->{control_in} } @nodes;
    my %mem; $mem{ join ',', $_->{inputs}->@* }++ for @reads;
    ok !( grep { $_ > 1 } values %mem ), "$name: no two pinned reads of \$@ share a memory version";
}

done_testing;
