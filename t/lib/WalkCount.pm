# ABOUTME: Loaded before -MO=SoN, it reports each loop body B::SoN walks more than once in
# ABOUTME: the process (`REWALK n file:line`): a sub walked again walks its loops again.
package WalkCount;
use v5.42.0;
use B ();
use SoN::FromOptree;

# A sub is walked once (wire v2, clause 3: loops "built Braun-style without the
# double walk"). A second walk of a sub walks each of its loop bodies again, so
# a loop body's start op met twice in one process is a sub walked twice (each
# loop belongs to one sub, and nothing else walks a body: the scouts are gone).
my %walks;
my %where;
my $orig = \&SoN::FromOptree::_walk_loop_body;
no warnings 'redefine';
*SoN::FromOptree::_walk_loop_body = sub {
    my $op = $_[1];
    if ( ref $op && $$op ) {
        $walks{$$op}++;
        $where{$$op} //= eval { my $c = $_[0]; my $gv = $c->GV; $gv->STASH->NAME . '::' . $gv->NAME } // '?';
    }
    goto &$orig;
};

CHECK {    # (after O.pm's: CHECK blocks run last-defined first; -c skips END)
    printf STDERR "REWALK %d %s\n", $walks{$_}, $where{$_} for sort { $where{$a} cmp $where{$b} || $a <=> $b } grep { $walks{$_} > 1 } keys %walks;
    printf STDERR "LOOPS %d\n", scalar keys %walks;
}

1;
