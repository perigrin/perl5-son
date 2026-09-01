# ABOUTME: Clearing an aggregate must be visible to later reads -- `@a = ()`
# ABOUTME: and `undef @a` both leave it empty, and neither is `@a = undef`.

use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub run_and_translate ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $out  = qx{$PERL $file 2>/dev/null};
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err" or return ''; local $/; <$e> } // '';
    return ( $out, ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub prog ( $w ) { return ( $w->{methods}{'main::__PROGRAM__'}{nodes} // [] ) }

# THREE DIFFERENT OPERATIONS, and conflating any two is a wrong answer:
#
#     my @a=(1,2,3); @a = ();     -> 0 elements   (cleared)
#     my @a=(1,2,3); undef @a;    -> 0 elements   (cleared)
#     my @a=(1,2,3); @a = undef;  -> 1 element    (one undef in it)
#
# The last is why `undef @a` cannot be modelled as a rebind to the Undef
# constant: that produces the ONE-ELEMENT array, not an empty one.

subtest 'an emptied array reads as empty afterwards' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'my @a = (1,2,3); @a = (); print scalar(@a);', 'clear-assign' );
    is $out, '0', 'perl reports it empty' or return;
    ok $w, 'it translates' or do { diag($err); return };

    my $ns = prog($w);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($count) = grep { ( $_->{op} // '' ) eq 'Count' } $ns->@*;
    ok $count, 'a Count reports the size' or return;

    # THE COUNTED NODE MUST BE THE EMPTY ONE. Reading the pre-clear literal
    # gives 3 where perl gives 0 -- a well-formed graph with a wrong number,
    # which no test asserting "it translates" can see.
    my $counted = $by{ ( $count->{inputs} // [] )->[0] // '' };
    ok $counted, 'and it counts something' or return;
    is scalar( ( $counted->{inputs} // [] )->@* ), 0,
        'it counts the EMPTIED aggregate, not the original three elements';
};

subtest 'undef on an array empties it, not rebinds it' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'my @a = (1,2,3); undef @a; print scalar(@a);', 'clear-undef' );
    is $out, '0', 'perl reports it empty' or return;

    # Either it refuses, or the count is right. What it must never do is
    # report 1 (the `@a = undef` shape) or 3 (the pre-clear literal).
    if ($w) {
        my $ns = prog($w);
        my %by = map { $_->{id} => $_ } $ns->@*;
        my ($count) = grep { ( $_->{op} // '' ) eq 'Count' } $ns->@*;
        ok $count, 'a Count reports the size' or return;
        my $counted = $by{ ( $count->{inputs} // [] )->[0] // '' };
        is scalar( ( $counted->{inputs} // [] )->@* ), 0,
            'it counts an empty aggregate';
    }
    else {
        like $err, qr/GAP/, 'or it refuses loudly';
    }
};

# `@a = undef` IS NOT A CLEAR. One undef element, not zero elements. Pinned so
# a future fix for the two above cannot quietly collapse this into them.
subtest 'assigning undef gives a one-element array' => sub {
    my ( $out, undef, undef ) = run_and_translate(
        'my @a = (1,2,3); @a = undef; print scalar(@a);', 'assign-undef' );
    is $out, '1', 'perl keeps one undef element';
};

done_testing;
