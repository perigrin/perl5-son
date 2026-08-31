# ABOUTME: s///e's replacement is a walkable subtree under pmreplroot.
# ABOUTME: /e runs once and becomes an operand; /ge runs per match and GAPs.
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
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub nodes ( $wire ) {
    return [ map { ( $wire->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $wire->{methods} // {} )->%* ) ];
}

# THE DEFECT. `s/b/ $n + 1 /e` was refused outright as "code replacement not
# yet lowered", on the reading that the replacement is opaque. It is not: it is
# an ordinary op subtree hanging off the subst's pmreplroot, and it is intact
# even under the rpeep suppression the walker runs with:
#
#     substcont -> null -> scope -> { ex-nextstate, add -> padsv $n, const 1 }
#
# What IS null under suppression is `pmreplstart`, the rpeep-computed exec
# shortcut into that subtree -- which is why looking there found nothing and
# the construct looked opaque. The tree itself was always reachable.
#
# NO NEW VOCABULARY. RegexSubst is a Value node and already carries inputs
# (today just the subject), so the computed replacement rides as a second
# operand.
subtest 's///e builds a RegexSubst with the replacement as an operand' => sub {
    my ( $wire, $err ) = translate(
        'my $s = "abc"; my $n = 5; $s =~ s/b/ $n + 1 /e; print $s;', 'e-once' );
    ok $wire, 'it translates rather than refusing' or diag($err), return;

    my ($rs) = grep { ( $_->{op} // '' ) eq 'RegexSubst' } nodes($wire)->@*;
    ok $rs, 'a RegexSubst is in the graph' or return;
    is scalar( ( $rs->{inputs} // [] )->@* ), 2,
        'subject AND computed replacement are both operands';

    my %by = map { $_->{id} => $_ } nodes($wire)->@*;
    my $repl = $by{ ( $rs->{inputs} // [] )->[1] // -1 };
    ok $repl, 'the second operand resolves' or return;
    is $repl->{op}, 'Add', 'and it is the COMPUTED value, not a literal';

    # THE STRING FIELD MUST BE EMPTY, not stale. It is only meaningful for a
    # literal replacement; leaving a value there when the real replacement is
    # an operand gives a consumer two contradictory answers, and the value it
    # picked up was an unrelated stack node ($n's 5, not the replacement).
    is( ( $rs->{fields}{replacement} // '' ), '',
        'the string replacement field is empty when the replacement is code' );
};

# /ge RUNS THE REPLACEMENT PER MATCH -- measured: `s/a/ $n++ /ge` on "aaa"
# yields "012" with $n at 3, while /e alone yields "0aa" with $n at 1. A
# side-effecting body that repeats is a loop, which a single operand cannot
# express, so it stays an honest refusal rather than a silent once-only lowering.
subtest 's///ge still refuses -- per-match execution is a loop' => sub {
    my ( undef, $err ) = translate(
        'my $s = "aaa"; my $n = 0; $s =~ s/a/ $n++ /ge; print $s;', 'ge' );
    like $err, qr/GAP:/, '/ge is refused';
    like $err, qr/per match|\/g/, '... naming why it differs from plain /e';
};

# A LITERAL REPLACEMENT IS UNCHANGED: no /e means no subtree, and the
# replacement stays the string field it has always been.
subtest 'a plain s/// keeps its string replacement' => sub {
    my ( $wire, $err ) = translate(
        'my $s = "abc"; $s =~ s/b/X/; print $s;', 'plain' );
    ok $wire, 'it translates' or diag($err), return;

    my ($rs) = grep { ( $_->{op} // '' ) eq 'RegexSubst' } nodes($wire)->@*;
    ok $rs, 'a RegexSubst is in the graph' or return;
    is $rs->{fields}{replacement}, 'X', 'the literal replacement is preserved';
    is scalar( ( $rs->{inputs} // [] )->@* ), 1, 'and it has only the subject';
};

# A CONSTANT-FOLDED /e REPLACEMENT IS THE LITERAL CASE. perl folds
# `s/a/ "X" . "Y" /e` at compile time and leaves pmreplroot NULL with PMf_EVAL
# still set -- so the subtree walk above has nothing to walk, and treating that
# absence as unreachable code refused a substitution that is simply constant.
# It falls through to the literal path instead, where the folded value is
# already on the stack.
subtest 'a folded /e replacement takes the literal path' => sub {
    my ( $wire, $err ) = translate(
        'my $s = "ab"; $s =~ s/a/ "X" . "Y" /e; print $s;', 'folded' );
    ok $wire, 'it translates' or diag($err), return;

    my ($rs) = grep { ( $_->{op} // '' ) eq 'RegexSubst' } nodes($wire)->@*;
    ok $rs, 'a RegexSubst is in the graph' or return;
    is $rs->{fields}{replacement}, 'XY',
        'the folded value is the string replacement';
    is scalar( ( $rs->{inputs} // [] )->@* ), 1,
        'and there is no code operand -- nothing was left to compute';
};

done_testing;
