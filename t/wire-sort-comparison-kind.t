# ABOUTME: A folded sort states its comparison kind and direction on the wire.
# ABOUTME: Three distinct programs used to arrive byte-identical.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub sort_call ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    return undef unless length $json;
    my $w = JSON::PP->new->decode($json);
    for my $g ( sort keys( ( $w->{methods} // {} )->%* ) ) {
        for my $n ( ( $w->{methods}{$g}{nodes} // [] )->@* ) {
            return $n if ( $n->{op} // '' ) eq 'Call'
                      && ( $n->{fields}{name} // '' ) eq 'sort';
        }
    }
    return undef;
}

# THE DEFECT, reported by chalk. perl FOLDS the standard comparators into flags
# on the sort op, which is why they carry no block -- but those flags did not
# reach the wire, so three programs with three different answers arrived
# byte-identical:
#
#     sort { $a <=> $b } (3,1,2)   perl 1     Call(sort) fields identical
#     sort { $b <=> $a } (3,1,2)   perl 3     Call(sort) fields identical
#     sort (3,1,2)                 perl 1     Call(sort) fields identical
#
# Nothing was dropped -- the list is all there -- but a consumer picking one
# behaviour silently miscompiles the other two. That is a silent AMBIGUITY
# rather than a silent drop, and worse than the refusal it sits beside.
#
# BARE SORT IS STRING COMPARISON, which is the row that bites ordinary code:
# `sort (10, 9, 100)` is `10 100 9`, not `9 10 100`. A consumer assuming
# numeric because the common case looks numeric would be wrong on plain perl.
#
# The facts are on the op (OPpSORT_NUMERIC 0x1, OPpSORT_DESCEND 0x10), so this
# is T1 stating what the program says, not an inference.
subtest 'a numeric ascending sort says so' => sub {
    my $n = sort_call( 'my @s = sort { $a <=> $b } (3,1,2); print $s[0];', 'asc-num' );
    ok $n, 'the sort Call is on the wire' or return;
    is $n->{fields}{sort_cmp},   'numeric',   'comparison is numeric';
    is $n->{fields}{sort_order}, 'ascending', 'order is ascending';
};

subtest 'a numeric descending sort says so' => sub {
    my $n = sort_call( 'my @s = sort { $b <=> $a } (3,1,2); print $s[0];', 'desc-num' );
    ok $n, 'the sort Call is on the wire' or return;
    is $n->{fields}{sort_cmp},   'numeric',    'comparison is numeric';
    is $n->{fields}{sort_order}, 'descending', 'order is descending';
};

# A BARE sort AND `sort { $a cmp $b }` ARE THE SAME OPERATION -- string
# ascending -- and both must say string, not numeric.
subtest 'a bare sort is string comparison' => sub {
    for my $src ( 'my @s = sort (10,9,100); print $s[0];',
                  'my @s = sort { $a cmp $b } ("b","a"); print $s[0];' ) {
        my $n = sort_call( $src, 'str' );
        ok $n, "the sort Call is on the wire: $src" or next;
        is $n->{fields}{sort_cmp}, 'string', '...and says string comparison';
    }
};

# THE THREE FORMS MUST NOT BE IDENTICAL, which is the property the whole change
# exists for. Asserting each field separately would pass if every sort reported
# the same thing.
subtest 'the three folded forms are distinguishable' => sub {
    my @sig = map {
        my $n = sort_call( "my \@s = $_->[0] (3,1,2); print \$s[0];", $_->[1] );
        $n ? ( ( $n->{fields}{sort_cmp} // '?' ) . '/'
             . ( $n->{fields}{sort_order} // '?' ) ) : 'missing';
    } ( [ 'sort { $a <=> $b }', 'a' ],
        [ 'sort { $b <=> $a }', 'b' ],
        [ 'sort',               'c' ] );

    is scalar( keys %{ { map { $_ => 1 } @sig } } ), 3,
        "all three forms carry a distinct signature (@sig)";
};

done_testing;
