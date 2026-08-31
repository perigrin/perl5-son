# ABOUTME: The wire does not carry perl's pad-slot index -- it means nothing
# ABOUTME: to a consumer, and the producer calls it unstable.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub wire ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    die "no JSON for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

sub nodes ( $w ) {
    return [ map { ( $w->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $w->{methods} // {} )->%* ) ];
}

# `targ` IS PERL'S SCRATCHPAD INDEX -- which pad slot a lexical occupies in one
# CV. It is an artifact of how perl stores locals, says nothing about what a
# program means, and PadAccess::content_hash deliberately excludes it: pad
# indices are CV-local and unstable across compilation units, so two
# semantically identical reads at different indices MUST hash-cons together.
#
# Shipping it invited a consumer to key on a number the producer itself calls
# unstable. Nothing behavioral read it -- measured, the only node-level readers
# were the text renderer (diagnostics) and the serializer.
subtest 'a PadAccess does not ship its pad index' => sub {
    my $w = wire( 'my $r; { my $x = 5; $r = \$x; $x = 9; print $x; }', 'noindex' );
    my @pads = grep { ( $_->{op} // '' ) eq 'PadAccess' } nodes($w)->@*;

    ok scalar(@pads), 'the graph has PadAccess nodes' or return;
    is scalar( grep { exists $_->{fields}{targ} } @pads ), 0,
        'none of them carry a targ';
    is scalar( grep { defined $_->{fields}{varname} } @pads ), scalar(@pads),
        'and all of them still carry the varname a consumer can use';
};

# IDENTITY DOES NOT DEPEND ON IT. Two shadowed `my $x` in sibling scopes are
# distinct variables -- perl gives them pad slots 3 and 4 -- and they stay
# distinct nodes on the wire without the index, because their MEMORY inputs
# differ. That is what keeps them apart, not the pad slot.
subtest 'shadowed lexicals stay distinct without the index' => sub {
    my $w = wire( 'my $r1; my $r2;
{ my $x = 5; $r1 = \$x; $x = 9; print $x; }
{ my $x = 7; $r2 = \$x; $x = 3; print $x; }', 'shadow' );

    my @pads = grep { ( $_->{op} // '' ) eq 'PadAccess' } nodes($w)->@*;
    ok scalar(@pads) > 1, 'several PadAccess nodes' or return;

    my %ids = map { $_->{id} => 1 } @pads;
    is scalar( keys %ids ), scalar(@pads),
        'each read is its own node -- none collapsed into another';
};

done_testing;
