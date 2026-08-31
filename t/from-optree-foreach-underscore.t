# ABOUTME: `for (LIST)` iterates $_ -- the package scalar, keyed main::$_.
# ABOUTME: OPpITER_DEF marks the implicit form; the stack name node is not $_.
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

# THE DEFECT. `for (1..3) { print }` was refused as "foreach with an implicit
# $_ iterator". The refusal keyed on the stack NAME NODE not being a Constant
# -- and measured, it is not: it comes back as an ArgsSource, because resolving
# `gv[*_]` conflated $_ with the argument array @_. That is the same sigil
# hazard the match handler's comment records ("`$_` and `@_` are different
# variables sharing the glob name `_`").
#
# The name node is not needed. perl marks the implicit form on the op itself:
# OPpITER_DEF (private 0x8), measured 0x8 for `for (1..3)` and 0x0 for
# `for $main::t (1..3)`. The iterator is then keyed main::$_, exactly as the
# match handler and the s/// handler key it.
subtest 'an implicit $_ foreach translates' => sub {
    my ( $w, $err ) = translate( 'my $n = 0; for (1..3) { $n = $n + 1 } print $n;',
                                 'implicit-iter' );
    ok $w, 'it translates rather than GAPping' or diag($err), return;
    unlike $err, qr/implicit \$_/, 'no implicit-$_ GAP';

    my @ops = map { $_->{op} // '' } nodes($w)->@*;
    ok scalar( grep { $_ eq 'Loop' } @ops ), 'a Loop node exists';
    ok scalar( grep { $_ eq 'Phi'  } @ops ), 'and an induction Phi';
};

# THE BODY MUST SEE $_. Binding the iterator under the wrong key would still
# build a Loop and a Phi; the body's read of $_ would simply resolve elsewhere.
subtest 'the body reads $_ as the iteration value' => sub {
    my ( $w, $err ) = translate( 'my $s = 0; for (1..3) { $s = $s + $_ } print $s;',
                                 'body-reads' );
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my @add = grep { ( $_->{op} // '' ) eq 'Add' } $ns->@*;
    ok scalar(@add), 'the body adds' or return;

    my $reads_phi = 0;
    for my $a (@add) {
        my @in = map { $by{$_} } ( $a->{inputs} // [] )->@*;
        $reads_phi = 1 if grep { ( $_->{op} // '' ) eq 'Phi' } @in;
    }
    ok $reads_phi, '$_ resolves to the induction Phi, not to @_ or a fresh node';
};

# THE EXPLICIT FORMS ARE UNCHANGED -- a lexical iterator keys by pad targ and a
# package one by stash::$name, and neither should be caught by the $_ path.
subtest 'lexical and package iterators still translate' => sub {
    for my $src (
        'my $n = 0; for my $i (1..3) { $n = $n + $i } print $n;',
        'my $n = 0; for $main::t (1..3) { $n = $n + 1 } print $n;',
    ) {
        my ( $w, $err ) = translate( $src, 'other-iter' );
        ok $w, "translates: $src" or diag($err);
    }
};

# `for (@a)` -- implicit $_ over an ARRAY -- also keys correctly now. The glob
# is the LAST stack element whatever the bounds count (one for an array, two
# for a range), so it cannot be split off by arity the way a NAMED package
# iterator's is; measured, leaving it in place made `for (@a)` read as a
# two-element shape, [ArrayRef, ArgsSource], and miss every bounds branch.
#
# A body that ACCUMULATES over it still GAPs, on an older limit that has
# nothing to do with $_ (a loop-carried value losing its stamp across the
# back-edge). Pinning the shape here, not that.
subtest 'for (@a) reaches the array bounds branch' => sub {
    my ( undef, $err ) = translate(
        'my @a = (4,5,6); for (@a) { print }', 'array-iter' );
    unlike $err, qr/unrecognized bounds shape/,
        'the glob is not counted as a bound';
    unlike $err, qr/implicit \$_/, 'and $_ is keyed, not refused';
};

done_testing;
