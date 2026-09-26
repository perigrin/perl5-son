# ABOUTME: a glob assignment whose RHS type is known is a typed binding, not a GAP.
# ABOUTME: only an all-slot Glob RHS, or a type unknown after inference, refuses.
use 5.42.0;
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
    my $json = qx{$PERL -Ilib -MO=SoN,json,not_package=SoN $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub nodes ( $wire, $method ) {
    return ( ( $wire->{methods}{$method} // {} )->{nodes} // [] );
}

# The binding's TARGET is an EntryDef, and its SIGIL is the aliased slot --
# `*crackers = \@SRC` binds `@crackers`. Nothing new is needed on the wire to
# say which slot: the sigil already IS the slot, and it is already part of an
# EntryDef's identity ("$_ and @_ are DIFFERENT variables"), so a later read of
# `@crackers` hash-conses to the very node this write targets.
sub binding ( $wire, $method ) {
    my @n = nodes( $wire, $method )->@*;
    my %by = map { $_->{id} => $_ } @n;
    my ($w) = grep { ( $_->{op} // '' ) eq 'EntryWrite' } @n;
    return ( undef, undef ) unless $w;
    return ( $w, $by{ ( $w->{inputs} // [] )->[0] // -1 } );
}

# THE DEFECT. Every GAP in the producer fires during the optree walk, before
# any type is inferred -- so the glob assignment refused for want of a fact
# B::SoN's own Ref rule derives ONE PHASE LATER. Measured at the refusal point:
#
#     *foo3 = sub {...}   AnonSub    stamp=CodeRef    <- known even at the walk
#     *foo3 = \&SRC       Ref        stamp=Unknown    <- Ref rule: CodeRef
#     *crackers = \@SRC   Ref        stamp=Unknown    <- Ref rule: ArrayRef
#     *d = \$S            Ref        stamp=Unknown    <- Ref rule: ScalarRef
#     *D = *SRC           Constant   stamp=Glob       <- every slot at once
#     *FH = shift         Call       stamp=Unknown    <- a runtime fact
#
# and lib/B/SoN.pm's "\OPERAND: the reference kind follows the operand's kind"
# maps Array -> ArrayRef, Code -> CodeRef, Glob -> GlobRef on exactly those
# Ref nodes. So four of the six were refused for a phase artifact, not a fact.
#
# THE RHS'S TYPE SELECTS THE BINDING -- that is dispatch on type, which is why
# modelling it as a store into one of four locations never fit:
#
#     *D = \@SRC  ->  @D bound, $D still undef     the ARRAY slot alone
#     *D = \&SRC  ->  D() bound                    the CODE slot alone
#     *D = *SRC   ->  $D, @D and D() all bound     every slot
subtest 'a CodeRef RHS binds the code slot and is recorded, not refused' => sub {
    my ( $wire, $err ) = translate( <<'SRC', 'glob-coderef' );
sub SRC { "code" }
*foo3 = \&SRC;
SRC
    ok $wire, 'it translates rather than refusing' or diag($err), return;
    unlike $err, qr/GAP:.*glob/, 'no glob GAP is raised';

    my ( $w, $entry ) = binding( $wire, 'main::__PROGRAM__' );
    ok $w, 'the binding is an EntryWrite into the stash entry' or return;
    is( ( $entry->{fields}{sigil} // '' ), '&',
        'and its target names the slot the RHS type selects' );
    is( ( $entry->{fields}{symbol} // '' ), 'foo3', 'under the glob name' );
};

# A DECLARED ANON SUB IS THE SAME BINDING with the type known even earlier.
subtest 'an AnonSub RHS binds the code slot' => sub {
    my ( $wire, $err ) = translate( '*foo3 = sub { 42 };', 'glob-anonsub' );
    ok $wire, 'it translates' or diag($err), return;

    my ( $w, $entry ) = binding( $wire, 'main::__PROGRAM__' );
    ok $w, 'an EntryWrite carries it' or return;
    is( ( $entry->{fields}{sigil} // '' ), '&', 'the code slot is named' );
};

# AN ARRAY REF BINDS THE ARRAY SLOT ALONE. base/lex.t's `*R::crackers =
# \@array` is read back as `@R::crackers` -- proof the slot must follow the
# RHS type rather than being assumed to be a handle.
subtest 'an ArrayRef RHS binds the array slot' => sub {
    my ( $wire, $err ) = translate( <<'SRC', 'glob-arrayref' );
our @SRC = (1,2,3);
*crackers = \@SRC;
SRC
    ok $wire, 'it translates' or diag($err), return;

    my ( $w, $entry ) = binding( $wire, 'main::__PROGRAM__' );
    ok $w, 'an EntryWrite carries it' or return;
    is( ( $entry->{fields}{sigil} // '' ), '@',
        'the ARRAY slot, not a filehandle' );
};

# A SCALAR REF BINDS THE SCALAR SLOT.
subtest 'a ScalarRef RHS binds the scalar slot' => sub {
    my ( $wire, $err ) = translate( <<'SRC', 'glob-scalarref' );
our $S = "x";
*d = \$S;
SRC
    ok $wire, 'it translates' or diag($err), return;

    my ( $w, $entry ) = binding( $wire, 'main::__PROGRAM__' );
    ok $w, 'an EntryWrite carries it' or return;
    is( ( $entry->{fields}{sigil} // '' ), '$', 'the SCALAR slot' );
};

# CASE 2 STILL REFUSES, and for a DIFFERENT reason than case 3 -- a glob RHS
# aliases every slot at once, which no single typed binding expresses. The
# message must say which of the two it is; "aliases a symbol-table entry"
# conflated them.
# A GLOB RHS ALIASES EVERY SLOT AND THAT IS THE `*` SIGIL. This asserted a
# refusal whose reason -- "which no single typed binding expresses" -- was true
# and beside the point: `*` IS the binding that means every slot, and it was
# already what the producer's fallback supplied. Measured:
#
#     our @A=(1,2); *B = *A; print scalar(@A)
#       perl  2      ours  *main::B = *A;  -> 2
#
# The single-slot path is unaffected -- a leaf ref type still resolves to its
# sigil, asserted in the subtests above.
subtest 'a Glob RHS aliases every slot, and `*` says so' => sub {
    my ( $wire, $err ) = translate( <<'SRC', 'glob-glob' );
our @SRC = (1);
sub f { *D = *SRC; 1 }
SRC
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;
    ok $wire, 'and produces a wire' or return;

    # THE NODES COME THROUGH `nodes()`, which the other subtests use -- a first
    # draft treated translate()'s first return as the node list and died "Not an
    # ARRAY reference", because it is the whole wire.
    my ($target) = grep { ( $_->{op} // '' ) eq 'EntryDef'
                          && ( ( $_->{fields} // {} )->{symbol} // '' ) eq 'D' }
                   nodes( $wire, 'main::f' )->@*;
    ok $target, 'the target entry is in the graph' or return;
    is( ( $target->{fields} // {} )->{sigil}, '*',
        'and keeps the star, which is what "every slot" means' );
};


# CASE 3 IS A STATEMENT, NOT A REFUSAL. `*FH = shift` leaves every ref kind
# possible -- `shift` stamps Scalar -- and `*` says exactly that: one slot,
# chosen at runtime. The whole idiom round-trips:
#
#     sub f { *FH = shift; 1 } f(\*STDOUT); print FH "via alias\n";
#       perl  via alias      ours  via alias
#
# which is base/rs.t's shape, and getting there also needed the glob REF to keep
# its sigil -- `\(STDOUT)` is a reference to the bareword STRING and prints
# nothing, where `\*STDOUT` is a GlobRef.
subtest 'an RHS still Unknown after inference keeps the star' => sub {
    my ( $wire, $err ) = translate( <<'SRC', 'glob-unknown' );
sub f { *FH = shift; 1 }
SRC
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;
    ok $wire, 'and produces a wire' or return;

    my ($target) = grep { ( $_->{op} // '' ) eq 'EntryDef'
                          && ( ( $_->{fields} // {} )->{symbol} // '' ) eq 'FH' }
                   nodes( $wire, 'main::f' )->@*;
    ok $target, 'the target entry is in the graph' or return;
    is( ( $target->{fields} // {} )->{sigil}, '*',
        'and the slot stays unresolved rather than guessed' );
};

done_testing;
