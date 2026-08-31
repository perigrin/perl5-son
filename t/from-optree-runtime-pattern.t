# ABOUTME: =~ is a binop: Match(subject, pattern), whatever pushed what.
# ABOUTME: A stacked subject with a runtime pattern is two pops in push order.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub wire_for ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( undef, $err ) unless length $json;
    return ( JSON::PP->new->decode($json), $err );
}

sub nodes ( $wire ) {
    return [ map { ( $wire->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $wire->{methods} // {} )->%* ) ];
}

# THE DEFECT. `$g =~ $re` -- a PACKAGE subject with a RUNTIME pattern -- was
# refused as "a runtime pattern applied to a pushed subject not yet lowered",
# on the reasoning that two values were on the stack in an order that had to be
# established before either could be popped safely.
#
# But =~ is a BINOP. Match(subject, pattern) has an operand order because it is
# a binop, not one to be recovered. Measured, perl 5.42, OPf_STACKED (0x40)
# tracks THE SUBJECT and never the pattern:
#
#     my $s =~ $re    match()[$s]      targ, no S    subject in targ
#     our $g =~ $re   match() sKPS     S             subject stacked
#     my $s =~ /b/    match(/"b"/)[$s] targ, no S
#     our $g =~ /b/   match(/"b"/)sKPS S
#
# regcomp is OpMap SKIP ([1,undef,1]) and leaves the compiled matcher on the
# stack, so in the stacked+runtime case the stack holds SUBJECT then PATTERN --
# push order, which is exactly what determines pop order. Nothing is unknown.
subtest 'a package subject with a runtime pattern is a Match' => sub {
    my ( $wire, $err ) = wire_for(
        'our $g = "abc"; our $re = qr/b/; my $r = ($g =~ $re); print $r;',
        'pkg-runtime' );
    ok $wire, 'the program translates at all' or diag($err), return;

    my ($m) = grep { ( $_->{op} // '' ) eq 'Match' } nodes($wire)->@*;
    ok $m, 'it builds a Match node' or return;
    is $m->{stamp}, 'Boolean', 'a match yields a Boolean';
    is scalar( ( $m->{inputs} // [] )->@* ), 2, 'a binop: two operands';
};

# OPERAND ORDER IS THE POINT. Inverting the two pops is silent -- the graph
# still has a Match with two inputs -- so this asserts WHICH is which: the
# subject is the package variable, the pattern is the qr value.
subtest 'the subject is operand 0 and the pattern operand 1' => sub {
    my ( $wire, $err ) = wire_for(
        'our $g = "abc"; our $re = qr/b/; my $r = ($g =~ $re); print $r;',
        'pkg-order' );
    ok $wire, 'translates' or diag($err), return;

    my $ns = nodes($wire);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($m) = grep { ( $_->{op} // '' ) eq 'Match' } $ns->@*;
    ok $m, 'a Match exists' or return;

    my ( $subj, $pat ) = map { $by{$_} } ( $m->{inputs} // [] )->@*;
    ok $subj && $pat, 'both operands resolve' or return;

    # ASSERTED AGAINST THE OPTREE, NOT THE SOURCE. perl folds `our $g = "abc"`,
    # so the subject reaches the Match as a Constant string, not as a read of
    # $g -- the pattern is the qr Constant beside it. What discriminates the
    # two operands is their const_type, and inverting them would swap these.
    is( ( $subj->{fields}{const_type} // '' ), 'string',
        'operand 0 is the SUBJECT (the string), not the pattern' );
    is( ( $pat->{fields}{const_type} // '' ), 'regex',
        'operand 1 is the PATTERN (the qr), not the subject' );
};

# THE LEXICAL FORM IS UNCHANGED, and shares no pop with the above: its subject
# rides in the op's targ, so only the pattern is on the stack.
subtest 'a lexical subject with a runtime pattern still works' => sub {
    my ( $wire, $err ) = wire_for(
        'my $s = "abc"; my $re = qr/b/; my $r = ($s =~ $re); print $r;',
        'lex-runtime' );
    ok $wire, 'translates' or diag($err), return;
    my ($m) = grep { ( $_->{op} // '' ) eq 'Match' } nodes($wire)->@*;
    ok $m, 'it builds a Match node';
    is scalar( ( $m->{inputs} // [] )->@* ), 2, 'two operands' if $m;
};

# AND THE LITERAL FORMS STAY RegexMatch, which carries its pattern inline.
subtest 'a literal pattern is still a RegexMatch' => sub {
    my ( $wire, $err ) = wire_for(
        'our $g = "abc"; my $r = ($g =~ /b/); print $r;', 'pkg-literal' );
    ok $wire, 'translates' or diag($err), return;
    ok scalar( grep { ( $_->{op} // '' ) eq 'RegexMatch' } nodes($wire)->@* ),
        'a stacked subject with a literal pattern is a RegexMatch';
};

done_testing;
