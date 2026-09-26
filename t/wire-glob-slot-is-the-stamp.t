# ABOUTME: `*X = EXPR` binds the slot named by EXPR's TYPE, and the lattice
# ABOUTME: already relates those types -- so an imprecise stamp is not a refusal.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub write_tmp ($src, $tag) {
    my $f = "$dir/$tag." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    return $f;
}

sub runs ($src) {
    my $f = write_tmp( $src, 'r' );
    my $o = qx($^X $f 2>&1);
    unlink $f;
    return $o;
}

sub emit ($src) {
    my $f = write_tmp( $src, 'g' );
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
    unlink $f;
    my $data = eval { JSON::PP->new->decode($j) };
    return ( undef, $e ) unless $data && $data->{methods}{'main::__PROGRAM__'};
    my $out = eval { SoN::Deparse->new->render($data) };
    return ( undef, ( $@ || 'refused' ) ) unless defined $out;
    return ( $out, undef );
}

sub round_trips ($src, $name) {
    my ( $out, $why ) = emit($src);
    ok defined $out, "$name renders" or do { diag $why; return };
    is runs($out), runs($src), "$name round-trips" or diag $out;
}

# THE SLOT IS THE STAMP. `*X = EXPR` binds the glob slot chosen by EXPR's TYPE,
# and every behaviour follows from one rule -- how many ref kinds sit under the
# stamp in the lattice:
#
#     exactly one   -> that slot, statically resolved
#     five          -> one slot, kind chosen at runtime   (Scalar, Ref)
#     none, Glob/GlobRef/Str -> every slot
#
# Measured against the real lattice, `is_subtype_of` answers it:
#
#     Scalar     ArrayRef,HashRef,CodeRef,ScalarRef,GlobRef
#     Ref        ArrayRef,HashRef,CodeRef,ScalarRef,GlobRef
#     ArrayRef   (none)
#     Str        (none)
#
# so no new table is needed -- `%SLOT` keeps the four leaves and the rest is a
# query over types the lattice already relates.

# READING THE ALIAS DROPS THE SOURCE'S STORE, and this is the sharpest case in
# the file. Measured:
#
#     *crackers = \@OTHER; print "@OTHER"      7 8   store kept
#     *crackers = \@OTHER; print "@crackers"   ---   THE STORE IS GONE
#
# The pass replaces `crackers`'s EntryDef `sigil='*'` with a fresh `sigil='@'`,
# and a later read of `@crackers` hash-conses to THAT node -- so the alias read
# and the bind TARGET become one node and `@OTHER = (7,8)` loses its
# reachability. It compiles, runs, and prints nothing: a silent wrong answer, and
# the reason no census caught it is that the pass reports this case as SUCCESS.
#
# Keeping `sigil='*'` removes the collision by construction: a glob target and
# an array read are different nodes because they are different things.
subtest 'reading the alias keeps the source store' => sub {
    my $src = <<'SRC';
our @OTHER = (7, 8);
*crackers = \@OTHER;
print "@crackers\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    my $todo = todo 'the EntryDef rewrite conses the alias onto the bind target';
    is runs($out), runs($src), 'the aliased array has its elements'
        or diag $out;
};

subtest 'one ref kind under the stamp resolves statically' => sub {
    # READ THROUGH THE SOURCE NAME, which is the half that works today -- the
    # alias read is pinned in its own subtest above.
    round_trips( <<'SRC', 'an ArrayRef bind' );
our @SRC = (1, 2, 3);
*crackers = \@SRC;
print "@SRC\n";
SRC

    round_trips( <<'SRC', 'a ScalarRef bind' );
our $S = "sc";
*T = \$S;
print "$S\n";
SRC

    # A CODEREF BIND IS THE SECOND-ORDER REFUSAL, arriving from a third
    # direction. `*alias = \&orig` populates the glob's CODE slot, and a call
    # to `alias` then refuses with
    #
    #     GAP: a call to `main::alias`, which is not in the graph
    #
    # -- because the bind is modelled as a VARIABLE rather than as a symbol-table
    # operation, so the code slot it fills is invisible to callers. The producer
    # does not refuse; the deparser does, and it names the CALLER.
    my $src = <<'SRC';
sub orig { "called" }
*alias = \&orig;
print alias(), "\n";
SRC
    my ( $out, $why ) = emit($src);
    my $todo = todo 'a bound code slot is not visible to a callsite';
    ok defined $out, 'a CodeRef bind renders' or do { diag $why; return };
    is runs($out), runs($src), 'a CodeRef bind round-trips' or diag $out;
};

# EACH SLOT IS INDEPENDENT, which is what makes a glob four things rather than
# one. Measured: binding `$` leaves a previously bound `@` standing.
subtest 'the slots do not clobber each other' => sub {
    # READ THROUGH THE SOURCES. Reading @T/$T would hit the alias drop pinned
    # in the first subtest, which would make this fail for a different reason
    # than the one it is about.
    round_trips( <<'SRC', 'an array bind then a scalar bind' );
our @A = (1, 2);
our $S = "sc";
*T = \@A;
*T = \$S;
print scalar(@A), " $S\n";
SRC
};

# A GLOB OPERAND IS EVERY SLOT, and that is an EXPRESSION of what the source
# says -- not "no single typed binding expresses this", which is a statement
# about a model that made a glob one variable.
subtest 'a glob operand binds every slot' => sub {
    my $src = <<'SRC';
our @A = (1, 2);
our $A = "sc";
*B = *A;
our @B; our $B;
print scalar(@B), " $B\n";
SRC
    my ( $out, $why ) = emit($src);
    my $todo = todo 'a Glob-stamped bind is not yet expressible';
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'every slot reaches through' or diag $out;
};

# FIVE REF KINDS UNDER THE STAMP IS A STATEMENT, not a missing answer. A `shift`
# stamps Scalar -- probed on perl's own base/rs.t, `type=Scalar value_op=Call` --
# which says "one slot, kind determined at runtime". The emission is the source
# spelling, which perl's own deparse produces for this too (`*FH = shift()`).
subtest 'an imprecise stamp still lowers' => sub {
    my $src = <<'SRC';
our $S = "sc";
sub bind_it { *T = shift }
bind_it(\$S);
our $T;
print "$T\n";
SRC
    my ( $out, $why ) = emit($src);
    my $todo = todo 'a Scalar-stamped bind is not yet expressible';
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'the runtime slot reaches through' or diag $out;
};

# AND IT MUST STILL REFUSE NOTHING SILENTLY. Whatever happens to the cases
# above, a bind whose operand type cannot be expressed must GAP rather than
# guess a slot -- a wrong slot is a wrong program, not a missing feature.
subtest 'no bind is resolved to a guessed slot' => sub {
    my $src = <<'SRC';
our @A = (1, 2);
*B = *A;
our @B;
print scalar(@B), "\n";
SRC
    my ( $out, $why ) = emit($src);
    if ( defined $out ) {
        unlike $out, qr/^\@main::B = /m,
            'not emitted as a plain array store' or diag $out;
    }
    else {
        like $why, qr/GAP:/, 'refuses by name rather than guessing' or diag $why;
    }
};

done_testing;
