# ABOUTME: A block eval's (and a try's) caught die stores $@ after its catch: a version of its
# ABOUTME: own, so a read after the eval does not share the version of one in it.

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
    # (wire v2's `eval` profile: the caught die's $@ is a store, after the catch)
    my @catches = grep { $_->{op} eq 'Region' && $_->{fields}{catch} } @nodes;
    ok scalar(@catches), "$name: the evals have their catches";
    for my $r (@catches) {
        ok( ( grep { $_->{op} eq 'EntryWrite' && ( $_->{control_in} // -1 ) == $r->{id}
                     && ( $by_id{ $_->{inputs}[0] }{fields}{symbol} // '' ) eq '@' } @nodes ),
            "$name: eval $r->{fields}{eval_id}'s catch stores \$@, a version of its own" );
    }
    my @reads = grep { $_->{op} eq 'EntryDef' && ( $_->{fields}{symbol} // '' ) eq '@' && defined $_->{control_in} } @nodes;
    my %mem; $mem{ $_->{mem_in} // q(none) }++ for @reads;
    ok !( grep { $_ > 1 } values %mem ), "$name: no two pinned reads of \$@ share a memory version";
}

done_testing;
