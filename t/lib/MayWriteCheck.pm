# ABOUTME: Loaded before -MO=SoN, it compares each loop's syntactic may-write scan with the
# ABOUTME: scout's answer and prints `MISS key where` to STDERR for a key the scan missed.
package MayWriteCheck;
use v5.42.0;
use SoN::FromOptree;

# The scout walks the body and says which slots it rebinds; the scan reads the
# ops and says which it may write (wire v2 plan, 5.2 and Q6). The scan must be
# a superset, or stage 9b's Braun header misses a Phi.
my $orig = \&SoN::FromOptree::_scout_mutated_targs;
no warnings 'redefine';
*SoN::FromOptree::_scout_mutated_targs = sub {
    my @r = $orig->(@_);
    return @r if $SoN::FromOptree::IN_SCOUT;
    my $w = SoN::FromOptree::_may_write_targs( $_[1] );
    for my $k ( grep { !$w->{$_} } $r[0]->@* ) {
        my ( $op, %seen ) = ( $_[1] );
        $op = $op->next while ref $op && $$op && !$op->isa('B::COP') && !$seen{$$op}++;
        printf STDERR "MISS %s %s\n", $k, ref $op && $$op && $op->isa('B::COP') ? $op->file . ':' . $op->line : '?';
    }
    return @r;
};

1;
