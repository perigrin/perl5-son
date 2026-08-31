# ABOUTME: `foreach $t (...)` iterates a PACKAGE scalar -- keyed by stash::$name.
# ABOUTME: A lexical iterator is keyed by pad targ; both live in one scope map.
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

# THE DEFECT. `foreach $t (1..3)` was refused because enteriter's targ is 0 --
# a package iterator has no pad slot. But the walker already has a key for a
# package scalar: _stash_key gives 'main::$t', and the scope map is a plain
# hash that holds pad-targ keys and stash keys side by side.
#
# MEASURED, the glob is on the stack. rv2gv is OpMap SKIP, so pop_to_mark
# returns THREE elements where a lexical loop returns two:
#
#     lexical:  Constant(1) | Constant(3)                  targ=2
#     package:  Constant(1) | Constant(3) | Constant(t)    targ=0
#
# The iterator name rides LAST, as a Constant carrying the bareword. So the
# bounds are elements 0..1 and the name is the tail -- which also means the
# shape check must not count the glob as a bound.
subtest 'a package-scalar iterator translates' => sub {
    my ( $w, $err ) = translate(
        'my $n = 0; foreach $t (1..3) { $n = $n + 1 } print $n;', 'pkg-iter' );
    ok $w, 'it translates rather than refusing' or diag($err), return;
    unlike $err, qr/non-lexical iterator/, 'no iterator GAP';

    my @ops = map { $_->{op} // '' } nodes($w)->@*;
    ok scalar( grep { $_ eq 'Loop' } @ops ), 'a Loop node exists';
    ok scalar( grep { $_ eq 'Phi'  } @ops ), 'and an induction Phi';
};

# THE BODY MUST SEE THE ITERATOR. Binding it under the wrong key would still
# build a Loop and a Phi -- the body's read of $t would just resolve to
# something else, or to nothing.
subtest 'the loop body reads the iterator variable' => sub {
    my ( $w, $err ) = translate(
        'my $s = 0; foreach $t (1..3) { $s = $s + $t } print $s;', 'pkg-read' );
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($add) = grep { ( $_->{op} // '' ) eq 'Add' } $ns->@*;
    ok $add, 'the body adds' or return;

    my @in = map { $by{$_} } ( $add->{inputs} // [] )->@*;
    ok scalar( grep { ( $_->{op} // '' ) eq 'Phi' } @in ),
        'and one operand is the induction Phi -- $t resolved to the iterator';
};

# A LEXICAL ITERATOR IS UNCHANGED. It keys by pad targ and takes two bounds;
# a fix that mixed the two shapes would break the form that already worked.
subtest 'a lexical iterator still translates' => sub {
    my ( $w, $err ) = translate(
        'my $n = 0; foreach my $i (1..3) { $n = $n + $i } print $n;', 'lex-iter' );
    ok $w, 'it translates' or diag($err), return;
    my @ops = map { $_->{op} // '' } nodes($w)->@*;
    ok scalar( grep { $_ eq 'Loop' } @ops ), 'a Loop node exists';
};

done_testing;
