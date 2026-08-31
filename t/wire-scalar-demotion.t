# ABOUTME: An address-taken scalar leaves value-SSA and lives in memory.
# ABOUTME: Store is Assign(Access,value) on the memory chain; reads observe it.
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
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub nodes ( $w ) {
    return [ map { ( $w->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $w->{methods} // {} )->%* ) ];
}

# THE DEFECT. `\$x` was refused outright: "scalar demotion is not built yet".
# The RULE the refusal rests on is right and every SSA IR agrees with it --
# LLVM's mem2reg promotes an alloca only when it is used solely by loads and
# stores, GCC gives an aliased variable virtual operands, Go and Cranelift do
# not promote `addrtaken` locals. A write through a reference must be visible
# to every later read of the name, and a value binding cannot say that:
#
#     my $x = 5; my $r = \$x; $$r = 9; print $x;    # perl prints 9
#
# But the MECHANISM was already here and general. Aggregates have used it since
# memory-SSA landed: a store is Assign(lvalue, value) pinned to control and
# becoming the new memory version, a later read takes that version as an input,
# and StackSim::merge builds a memory Phi when two arms differ. None of that is
# aggregate-specific -- it threads whatever set_memory was given.
#
# So demotion needed the one piece with no analogue: deciding WHICH variables
# are address-taken, before the walk reaches their reads.
# WHAT IS BUILT, and what is not. The pre-pass and the read side are done and
# are asserted below. The WRITE side is not wired: the padsv_store demotion
# branch is never reached for this shape, so a store would be dropped and the
# read would observe MemStart instead of the stored value. Until that is fixed
# the construct stays REFUSED -- a plausible graph that silently loses a write
# is the one outcome the refuse-or-lower contract exists to prevent.
subtest 'taking a reference no longer refuses' => sub {
    my ( $w, $err ) = wire( 'my $x = 5; my $r = \$x; print $$r;', 'takeref' );
    ok $w, 'it translates' or diag($err), return;
    unlike $err, qr/scalar demotion|address-taken/, 'no demotion GAP';
};

# THE STORE IS ON THE MEMORY CHAIN, and each read carries the store that
# produced its value -- the memory-SSA shape an element access already uses:
#
#     PadAccess(MemStart) -> Assign -> PadAccess(Assign) -> Assign
#                                   -> PadAccess(Assign) -> Return
#
# A read threaded to MemStart when a store precedes it would be the silent
# failure: the graph looks well-formed and observes the wrong value.
subtest 'a demoted write is a store, and the next read observes it' => sub {
    require B;
    require SoN::OptSuppress;
    require SoN::FromOptree;

    SoN::OptSuppress::suppress_peep();
    my $cv = eval q{sub { my $x = 5; my $r = \$x; $x = 9; return $x }};
    SoN::OptSuppress::restore_peep();
    my $g = SoN::FromOptree->translate($cv);

    my @assign = grep { $_->operation eq 'Assign' } $g->nodes->@*;
    is scalar(@assign), 2, 'both writes became memory stores';

    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    ok $ret, 'the sub returns' or return;
    my $read = $ret->inputs->[0];
    is $read->operation, 'PadAccess', 'it returns a location read';
    is $read->inputs->[0]->operation, 'Assign',
        'threaded to a STORE, not to MemStart -- it observes the write';
};

# THE PRE-PASS IS DONE AND CORRECT. It is the piece that had no analogue in the
# existing machinery -- the aggregate path already threads stores and reads and
# StackSim::merge already builds memory Phis, none of it aggregate-specific.
subtest 'the address-taken pre-pass finds exactly the referenced variables' => sub {
    require B;
    require SoN::OptSuppress;
    require SoN::FromOptree;

    SoN::OptSuppress::suppress_peep();
    my %cv = (
        lexical => eval q{sub { my $x = 5; my $r = \$x; $$r = 9; $x }},
        package => eval q{sub { our $g = 5; my $r = \$g; $g }},
        none    => eval q{sub { my $y = 5; my $z = $y + 1; $z }},
    );
    SoN::OptSuppress::restore_peep();

    my $taken = sub ( $cv ) {
        [ sort keys %{ SoN::FromOptree::_address_taken(
            B::svref_2object($cv) ) } ]
    };

    is_deeply $taken->( $cv{lexical} ), [1],
        'a referenced lexical is marked by its pad targ';
    is_deeply $taken->( $cv{package} ), ['$main::g'],
        'a referenced package scalar is marked by stash, sigil and name';
    is_deeply $taken->( $cv{none} ), [],
        'and an ordinary scalar is not marked at all';
};

done_testing;
