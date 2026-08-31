# ABOUTME: `for (1,2,3)` iterates a literal list -- an array of known size.
# ABOUTME: The elements are already on the stack; no OPf_STACKED is set.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub translate ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub nodes ( $w ) {
    return [ map { ( $w->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $w->{methods} // {} )->%* ) ];
}

# THE DEFECT, and the most common GAP measured across perl's t/base, t/cmd and
# t/comp -- 7 occurrences, more than any other. `for my $i (1,2,3)` was refused
# as "foreach over a general list", on a guard that requires OPf_STACKED.
#
# A literal list does not set it: measured, `for my $i (1,2,3)` compiles to
# pushmark + three consts + `enteriter ... vK/LVINTRO` with NO S flag. The
# elements are simply on the stack, and pop_to_mark returns them:
# [Constant(1), Constant(2), Constant(3)].
#
# An N-element list IS an array of known size, so it reuses the array path
# wholesale -- bound by Count, body reading Subscript(arr, i). Nothing new is
# needed but the ArrayRef wrapper the anonlist handler already builds.
subtest 'a literal list foreach translates' => sub {
    my ( $w, $err ) = translate(
        'my $s = 0; for my $i (1,2,3) { $s = $s + $i } print $s;', 'lit-list' );
    ok $w, 'it translates rather than GAPping' or diag($err), return;
    unlike $err, qr/general list/, 'no general-list GAP';

    my @ops = map { $_->{op} // '' } nodes($w)->@*;
    ok scalar( grep { $_ eq 'Loop' } @ops ), 'a Loop node exists';
    ok scalar( grep { $_ eq 'Count' } @ops ), 'bounded by the element count';
};

# THE BODY MUST READ AN ELEMENT, not a fixed constant: a loop that bound $i to
# one list member would still build a Loop and a Count.
subtest 'the body reads the element, not a constant' => sub {
    my ( $w, $err ) = translate(
        'my $s = 0; for my $i (4,5,6) { $s = $s + $i } print $s;', 'elem' );
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my @add = grep { ( $_->{op} // '' ) eq 'Add' } $ns->@*;
    ok scalar(@add), 'the body adds' or return;

    my $reads_elem = 0;
    for my $a (@add) {
        my @in = map { $by{$_} } ( $a->{inputs} // [] )->@*;
        $reads_elem = 1 if grep { ( $_->{op} // '' ) eq 'Subscript' } @in;
    }
    ok $reads_elem, 'the iterator resolves to Subscript(list, i)';
};

# IMPLICIT $_ OVER A LIST takes the same path -- the two features compose.
subtest 'for (1,2,3) with implicit $_ translates' => sub {
    my ( $w, $err ) = translate(
        'my $s = 0; for (1,2,3) { $s = $s + $_ } print $s;', 'lit-underscore' );
    ok $w, 'it translates' or diag($err), return;
    unlike $err, qr/general list|implicit \$_/, 'neither GAP fires';
};

# A RANGE IS UNCHANGED. It sets OPf_STACKED and takes the counted-loop path,
# which a list fix must not divert.
subtest 'a range foreach still takes the range path' => sub {
    my ( $w, $err ) = translate(
        'my $s = 0; for my $i (1..3) { $s = $s + $i } print $s;', 'range' );
    ok $w, 'it translates' or diag($err), return;
    my @ops = map { $_->{op} // '' } nodes($w)->@*;
    is scalar( grep { $_ eq 'Count' } @ops ), 0,
        'a range is not bounded by a Count -- it keeps its own shape';
};

done_testing;
