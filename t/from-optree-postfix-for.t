# ABOUTME: `EXPR for LIST` is the same loop as `for (LIST) { EXPR }`.
# ABOUTME: Pins that, since it came free with the list/$_ iterator work.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub run_and_translate ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $out  = qx{$PERL $file 2>/dev/null};
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( $out, ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub nodes ( $w ) {
    return [ map { ( $w->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $w->{methods} // {} )->%* ) ];
}

# POSTFIX `for` IS A LOOP, not a third thing. Measured, it compiles to exactly
# the ops the block form does -- enteriter, iter, leaveloop, unstack -- so the
# same handler covers it and it began working when `for (1,2,3)` and the
# implicit-$_ iterator landed. Nothing here was written FOR postfix for; this
# pins that it stays working, since a regression would be silent.
subtest 'a postfix for over a literal list' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'my $n = 0; $n += $_ for (1,2,3); print $n;', 'pf-list' );
    is $out, '6', 'perl sums to 6' or return;
    ok $w, 'it translates' or diag($err), return;

    my @ops = map { $_->{op} // '' } nodes($w)->@*;
    ok scalar( grep { $_ eq 'Loop' } @ops ),  'a Loop node exists';
    ok scalar( grep { $_ eq 'Count' } @ops ), 'bounded by the element count';
};

# THE BODY MUST READ THE ELEMENT. A loop that bound $_ wrongly would still
# build a Loop and a Count, so assert the accumulator adds the element read.
subtest 'the body accumulates over the element, not a constant' => sub {
    my ( undef, $w, $err ) = run_and_translate(
        'my $n = 0; $n += $_ for (1,2,3); print $n;', 'pf-elem' );
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my $found = 0;
    for my $a ( grep { ( $_->{op} // '' ) eq 'Add' } $ns->@* ) {
        my @in = map { $by{$_} } ( $a->{inputs} // [] )->@*;
        $found = 1 if ( grep { ( $_->{op} // '' ) eq 'Phi' } @in )
                   && ( grep { ( $_->{op} // '' ) eq 'Subscript' } @in );
    }
    ok $found, 'Add(Phi, Subscript) -- accumulator plus element read';
};

# THE OTHER SPELLINGS take the same path: `foreach` is an alias, and the list
# may be an array rather than a literal.
subtest 'foreach and an array source lower the same way' => sub {
    my ( $out1, $w1, $e1 ) = run_and_translate(
        'my $n = 0; $n += $_ foreach (1,2,3); print $n;', 'pf-foreach' );
    is $out1, '6', 'foreach spelling: perl sums to 6';
    ok $w1, 'and it translates' or diag($e1);

    my ( $out2, $w2, $e2 ) = run_and_translate(
        'my @a = (1,2,3); my $n = 0; $n += $_ for @a; print $n;', 'pf-array' );
    is $out2, '6', 'array source: perl sums to 6';
    ok $w2, 'and it translates' or diag($e2);
};

done_testing;
