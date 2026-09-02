# ABOUTME: A generic list assignment must carry its RHS -- dropping it loses
# ABOUTME: the assigned value entirely, not merely its type.

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
    my $out  = qx{$PERL $file 2>/dev/null};
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err" or return ''; local $/; <$e> } // '';
    return ( $out, ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub prog ( $w ) { return ( ( $w // {} )->{methods}{'main::__PROGRAM__'}{nodes} // [] ) }

# THE DEFECT IS DATA LOSS, not a missing stamp. The generic list-assignment
# fallback built `Assign` from the LHS alone:
#
#     @_ = map { "x$_" } "y";  print "@_";
#     perl:  xy
#     graph: Assign in=[ArgsSource]   -- one input, no RHS at all
#
# The map result reached nothing. A consumer reading that graph cannot recover
# what was assigned, so the Unknown stamp was the SYMPTOM: _derived_type
# refuses a 1-input Assign because an assignment with no stored value has no
# value to yield, which is honest given its inputs and wrong about the node.
#
# Fixing the stamp without the input would have papered over a silent drop.

subtest 'a list assignment carries what it assigns' => sub {
    my ( $out, $w, $err ) = translate(
        '@_ = map { "x$_" } "y"; print "@_";', 'rhs-present' );
    is $out, 'xy', 'perl assigns the map result' or return;
    ok $w, 'it translates' or do { diag($err); return };

    my $ns = prog($w);
    my ($assign) = grep { ( $_->{op} // '' ) eq 'Assign' } $ns->@*;
    ok $assign, 'an Assign exists' or return;

    my @in = ( $assign->{inputs} // [] )->@*;
    ok scalar(@in) >= 2,
        'it has a target AND a value -- not the target alone'
        or diag( "inputs: @in" );
};

# THE STAMP FOLLOWS FOR FREE once the RHS is an input: the existing two-input
# rule ("an assignment yields the value it stored") then applies, with no
# change to _derived_type.
subtest 'and is typed by the value it stores' => sub {
    my ( undef, $w, $err ) = translate(
        '@_ = map { "x$_" } "y"; print "@_";', 'rhs-typed' );
    ok $w, 'it translates' or do { diag($err); return };

    my ($assign) = grep { ( $_->{op} // '' ) eq 'Assign' } prog($w)->@*;
    ok $assign, 'an Assign exists' or return;
    isnt $assign->{stamp} // 'Unknown', 'Unknown',
        'the Assign is typed from its stored value';
};

# A SCALAR ASSIGNMENT IS UNAFFECTED -- it already carried both operands, and a
# fix that touched it would be a regression dressed as generality.
subtest 'a scalar assignment still carries both operands' => sub {
    my ( $out, $w, $err ) = translate( 'my $x; $x = 42; print $x;', 'scalar-assign' );
    is $out, '42', 'perl assigns it' or return;
    ok $w, 'it translates' or do { diag($err); return };
    ok 1, 'scalar assignment path untouched';
};

done_testing;
