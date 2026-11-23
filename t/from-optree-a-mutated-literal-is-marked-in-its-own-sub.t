# ABOUTME: A literal mutated in one sub marks that literal only: not the node of the same id in a later sub.
# ABOUTME: %MUTATED_LITERALS is keyed by the node itself; ids are per graph, the table per compilation unit.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub graph_of ( $src, $sub ) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=-q,SoN,json $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->utf8->decode($out) };
    return $data ? $data->{methods}{$sub} : undef;
}

# THE TABLE WAS KEYED BY `$node->id`, and an id is a per-graph counter
# (`ArrayLiteral#4` in every sub that builds one fourth): `a`'s element store
# marked `b`'s untouched @b, whose `join` then read it through a pinned
# `PostfixDeref '@'` where `b` alone flattens the literal. Conservative, but a
# sub's wire depended on the subs compiled before it.
my $b = 'sub b { my @b = (1,2); return join(",", @b) }';
my $a = 'sub a { my @a = (1,2); $a[0] = 5; return join(",", @a) }';

my $alone = graph_of( $b, 'main::b' );
ok $alone, 'b translates alone' or diag 'no graph';
my $after = graph_of( "$a $b", 'main::b' );
ok $after, 'b translates after a' or diag 'no graph';

my $derefs = sub ($g) { scalar grep { $_->{op} eq 'PostfixDeref' } $g->{nodes}->@* };
is $derefs->($alone), 0, 'b alone flattens its literal';
is $derefs->($after), 0, 'b after a flattens its literal too: a\'s mark is a\'s';

# and the mark still works where it belongs: a's join reads the stored array
my $ga = graph_of( "$a $b", 'main::a' );
ok( ( grep { $_->{op} eq 'PostfixDeref' } $ga->{nodes}->@* ), 'a reads its mutated @a through memory' );

done_testing;
