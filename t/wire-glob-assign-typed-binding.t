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
subtest 'a Glob RHS aliases every slot and still refuses' => sub {
    my ( undef, $err ) = translate( <<'SRC', 'glob-glob' );
our @SRC = (1);
sub f { *D = *SRC; 1 }
SRC
    like $err, qr/GAP:/, 'it is refused';
    like $err, qr/every slot/i,
        '... naming all-slot aliasing, not an unknown slot';
};

# CASE 3 STILL REFUSES: `*FH = shift` is a Call whose stamp is Unknown even
# after inference, and the refusal now fires where the types are known rather
# than during the walk.
subtest 'an RHS still Unknown after inference refuses' => sub {
    my ( undef, $err ) = translate( <<'SRC', 'glob-unknown' );
sub f { *FH = shift; 1 }
SRC
    like $err, qr/GAP:/, 'it is refused';
    like $err, qr/not known until runtime|runtime/i,
        '... naming the slot as a runtime fact';
};

done_testing;
