# ABOUTME: A ListAppend must say whether it is map's contribution or grep's predicate.
# ABOUTME: The two shapes are indistinguishable on the wire, and they mean opposite things.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f;
    my $d = eval { JSON::PP->new->decode($j) } or return undef;
    return $d->{methods}{'main::__PROGRAM__'};
}

sub listappend ($src) {
    my $g = graph_of($src) or return undef;
    my ($la) = grep { ($_->{op} // '') eq 'ListAppend' } $g->{nodes}->@*;
    return undef unless $la;
    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    return { node => $la, by => \%by };
}

# THE PRODUCER KNOWS AND THE WIRE DOES NOT. FromOptree builds
#
#     grep  ListAppend(acc, ELEMENT, PREDICATE)
#     map   ListAppend(acc, CONTRIBUTION...)
#
# and its own comment says so: "for map the body's value(s), for grep the
# PREDICATE -- in which case what gets appended is the element, gated by that
# predicate". But ListAppend has NO serializer arm, so a consumer sees only a
# list of inputs.
#
# THE STAMP CANNOT RECOVER IT. Measured, all four shapes:
#
#     map { ($_,$_) }   in=[Phi Array, Subscript Int, Subscript Int]
#     map { () }        in=[Phi Array]
#     map { $_ > 1 }    in=[Phi Array, NumGt Boolean]      <- KEEP the Boolean
#     grep { $_ > 1 }   in=[Phi Array, Subscript Int, NumGt Boolean]
#
# `map { $_ > 1 }` has a Boolean CONTRIBUTION that must be appended, and
# grep's Boolean is a predicate that must not be. Same arity, same stamps,
# opposite meanings -- so any reader that guesses is wrong for one of them.
#
# A DEPARSE THAT GUESSES APPENDS THE PREDICATE: measured, `grep { $_ > 1 }
# (1,2,3)` rendered as an unconditional append gave `6 [1  2  3 ]` where perl
# gives `2 [2 3]`.
subtest 'the wire distinguishes map from grep' => sub {
    my $m = listappend('my @s = map { $_ > 1 } (1,2); print "@s\n";');
    my $g = listappend('my @s = grep { $_ > 1 } (1,2,3); print "@s\n";');
    ok $m && $g, 'both translate' or return;

    my $mf = $m->{node}{fields} // {};
    my $gf = $g->{node}{fields} // {};
    ok defined($mf->{collector}) && defined($gf->{collector}),
        'each ListAppend says which collector built it'
        or return;
    is $mf->{collector}, 'map',  'map says map';
    is $gf->{collector}, 'grep', 'grep says grep';
};

# THE SHAPES THAT ALREADY AGREE must keep working -- an empty contribution and
# a multi-value one are both map, and neither has a predicate.
subtest 'every map shape says map' => sub {
    for my $case (['my @s = map { ($_,$_) } (1,2); print "@s\n";', 'two per element'],
                  ['my @s = map { () } (1,2); print scalar(@s),"\n";', 'none'],
                  ['my @s = map { $_ * 2 } (1,2); print "@s\n";', 'one per element']) {
        my $r = listappend($case->[0]);
        ok $r, "$case->[1]: translates" or next;
        is +(($r->{node}{fields} // {})->{collector}), 'map', "$case->[1]: says map";
    }
};

done_testing;
