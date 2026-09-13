# ABOUTME: A pad-bound array or hash carries the variable name it was bound to.
# ABOUTME: Without it an element store has nothing to assign through -- `(1,2,3)[0]=7` is not Perl.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub graph_of ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    return $data->{methods}{'main::__PROGRAM__'};
}

# AN AGGREGATE IS REPRESENTED BY THE LITERAL THAT INITIALISED IT, and that
# literal had no name -- so there was no way to WRITE the container in Perl.
# An element store came out as
#
#     Assign(Subscript(ArrayLiteral, 0), 7)
#
# "store into element 0 of this literal", and `(1,2,3)[0] = 7` is not
# assignable. Reads survive because a list slice is legal; only stores need the
# name. Found by the deparse oracle
# (docs/plans/2026-09-13-an-aggregate-has-no-perl-spelling.md).
#
# The name is one expression away at the binding site: the target's `varname`
# is already read there for its SIGIL --
#
#     $sigil = substr($target->varname, 0, 1);
#
# -- so `@a` was in hand and only its first character kept.
subtest 'a pad-bound array carries its name in parts' => sub {
    my $g = graph_of('my @a = (1,2,3); print "@a\n";');
    ok $g, 'it translates' or return;

    my ($lit) = grep {
        $_->{op} eq 'ArrayLiteral' && ($_->{stamp} // '') eq 'Array'
    } $g->{nodes}->@*;
    ok $lit, 'the array is an Array-stamped ArrayLiteral' or return;
    is $lit->{fields}{sigil},  '@', 'and it carries the sigil';
    is $lit->{fields}{symbol}, 'a', '... and the bare symbol, not the blob';
};

subtest 'a pad-bound hash carries its name in parts' => sub {
    my $g = graph_of('my %h = (k => 1); print scalar(keys %h), "\n";');
    ok $g, 'it translates' or return;

    my ($lit) = grep {
        $_->{op} eq 'HashLiteral' && ($_->{stamp} // '') eq 'Hash'
    } $g->{nodes}->@*;
    ok $lit, 'the hash is a Hash-stamped HashLiteral' or return;
    is $lit->{fields}{sigil},  '%', 'and it carries the sigil';
    is $lit->{fields}{symbol}, 'h', '... and the bare symbol, not the blob';
};

# AN ANONYMOUS AGGREGATE HAS NO NAME TO CARRY, and must not acquire one. The
# stamp is what already separates them -- Array for `my @a`, ArrayRef for
# `[1,2,3]` -- so no new discriminator is needed.
subtest 'an anonymous aggregate carries no name' => sub {
    my $g = graph_of('my $r = [1,2,3]; print $$r[0], "\n";');
    ok $g, 'it translates' or return;

    my ($ref) = grep {
        $_->{op} eq 'ArrayLiteral' && ($_->{stamp} // '') eq 'ArrayRef'
    } $g->{nodes}->@*;
    ok $ref, 'the anon array is an ArrayRef-stamped ArrayLiteral' or return;
    ok !defined $ref->{fields}{symbol},
        'and carries no symbol -- there is no variable to name';
};

# TWO ARRAYS ARE TWO CONTAINERS, and the names must not collapse them. The
# nodes were already distinct (ArrayLiteral is not hash-consed); this checks
# the name does not become a reason to merge them.
subtest 'distinct arrays keep distinct names' => sub {
    my $g = graph_of('my @a = (1,2); my @b = (1,2); print "@a @b\n";');
    ok $g, 'it translates' or return;

    my @lits = grep {
        $_->{op} eq 'ArrayLiteral' && ($_->{stamp} // '') eq 'Array'
    } $g->{nodes}->@*;
    is scalar(@lits), 2, 'two arrays are two nodes' or return;
    my %names = map { (($_->{fields}{sigil} // '') . ($_->{fields}{symbol} // '?')) => 1 } @lits;
    is [sort keys %names], ['@a', '@b'], 'each carrying its own name';
};

done_testing;
