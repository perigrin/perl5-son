# ABOUTME: `$$r` reads through a scalar reference -- a PostfixDeref of the ref,
# ABOUTME: not a fresh variable and not a refusal.

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

# A SCALAR DEREF READS THROUGH A REFERENCE. The rv2sv handler covered the
# `gv` case (a package variable read) and refused everything else, so every
# `$$r` was a GAP -- including the `${\ EXPR }` idiom base/lex.t uses.
#
# The vocabulary already existed: PostfixDeref carries a sigil and is
# registered and serialized. FromOptree built it ZERO times.

subtest 'a scalar deref through a lexical ref lowers' => sub {
    my ( $out, $w, $err ) = translate(
        'my $v = "hi"; my $r = \$v; print $$r;', 'deref-lex' );
    is $out, 'hi', 'perl reads through the ref' or return;

    unlike $err, qr/GAP/, 'it does not GAP' or diag($err);
    my $ns = prog($w);
    ok scalar($ns->@*), 'the program graph is present' or return;

    my ($d) = grep { ( $_->{op} // '' ) eq 'PostfixDeref' } $ns->@*;
    ok $d, 'a PostfixDeref exists' or return;
    is $d->{fields}{sigil}, '$', 'and it carries the scalar sigil';
    is scalar( ( $d->{inputs} // [] )->@* ), 1,
        '... over exactly one operand, the reference';
};

# THE lex.t IDIOM. `${\ EXPR }` takes a ref to a temporary and immediately
# reads through it -- the construct that kept base/lex.t off 9/9.
subtest 'the ${\ EXPR } idiom lowers' => sub {
    my ( $out, $w, $err ) = translate( 'print "${\ q|x| }";', 'deref-idiom' );
    is $out, 'x', 'perl interpolates it' or return;
    unlike $err, qr/GAP/, 'it does not GAP' or diag($err);
    ok scalar( prog($w)->@* ), 'the program graph is present';
};

# A PACKAGE SCALAR READ IS NOT A DEREF and must keep its existing lowering --
# it is the case the handler already covered, and a fix that routed it through
# PostfixDeref would be a regression dressed as generality.
subtest 'a package scalar read is still an EntryDef, not a deref' => sub {
    my ( $out, $w, $err ) = translate( '$g = 5; print $g;', 'pkg-scalar' );
    is $out, '5', 'perl reads it' or return;
    ok scalar( prog($w)->@* ), 'it translates' or do { diag($err); return };

    is scalar( grep { ( $_->{op} // '' ) eq 'PostfixDeref' } prog($w)->@* ), 0,
        'no PostfixDeref -- a named variable is not a dereference';
};

done_testing;
