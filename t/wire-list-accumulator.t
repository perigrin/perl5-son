# ABOUTME: map/grep build a list whose length is not the input's.
# ABOUTME: ListAppend is the loop-carried accumulator that makes that expressible.
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

# WHY THIS NEEDED NEW VOCABULARY. map and grep are loops -- measured, they carry
# mapwhile/grepwhile exactly as `while` carries enterloop/leaveloop -- so the
# loop machinery applies. But the loop machinery had no ACCUMULATOR, and map's
# output length is not its input length:
#
#     map { ($_, $_) } (1,2)   -> 4 elements
#     map { () } (1,2)         -> 0 elements
#     grep { $_ > 1 } (1,2,3)  -> 2 elements
#
# Count(list) bounds the INPUT; nothing bounded the output. ListAppend is the
# loop-carried value that does: it takes the accumulator so far plus whatever
# this iteration produced, and yields the new accumulator. The existing loop-Phi
# machinery carries it across the back-edge like any other loop-carried value.
subtest 'grep filters and the graph says how' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'my @g = grep { $_ > 1 } (1,2,3); print scalar(@g);', 'grep' );
    is $out, '2', 'perl keeps two' or return;
    ok $w, 'it translates rather than GAPping' or diag($err), return;

    my @ops = map { $_->{op} // '' } nodes($w)->@*;
    ok scalar( grep { $_ eq 'Loop' } @ops ), 'a Loop node exists';
    ok scalar( grep { $_ eq 'ListAppend' } @ops ),
        'and a ListAppend accumulator';
};

# THE ACCUMULATOR MUST BE LOOP-CARRIED, not rebuilt each pass: its previous
# value has to reach it through the loop Phi, or the result is one iteration's
# output rather than all of them.
subtest 'the accumulator is carried across the back-edge' => sub {
    my ( undef, $w, $err ) = run_and_translate(
        'my @g = grep { $_ > 1 } (1,2,3); print scalar(@g);', 'grep-phi' );
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($app) = grep { ( $_->{op} // '' ) eq 'ListAppend' } $ns->@*;
    ok $app, 'a ListAppend exists' or return;

    my @in = map { $by{$_} } ( $app->{inputs} // [] )->@*;
    ok scalar( grep { ( $_->{op} // '' ) eq 'Phi' } @in ),
        'its accumulator input is a loop Phi';
};

# map APPENDS THE BODY VALUE, which is what distinguishes it from grep: grep
# appends the ELEMENT when the body is true, map appends the body's own result.
subtest 'map appends the body value' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'my @m = map { $_ * 2 } (1,2); print "@m";', 'map' );
    is $out, '2 4', 'perl doubles each' or return;
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($app) = grep { ( $_->{op} // '' ) eq 'ListAppend' } $ns->@*;
    ok $app, 'a ListAppend exists' or return;

    my @in = map { $by{$_} } ( $app->{inputs} // [] )->@*;
    ok scalar( grep { ( $_->{op} // '' ) eq 'Multiply' } @in ),
        'the appended value is the body result, not the raw element';
};

# THE TYPE OF A LIST IS List. The input list a map/grep iterates is built by
# the same ArrayLiteral every other list site uses, and every one of THOSE
# stamps explicitly -- `my @a = (1,2,3)` is Array, `[1,2,3]` is ArrayRef. Left
# unstamped this site fell through to Unknown, the lattice TOP, which asserts
# nothing about a value whose type is known at construction: a literal list is
# a List, and List is a real member sitting directly under Unknown with
# Array/Hash/Scalar beneath it.
#
# Unknown here is not merely imprecise. It is the one stamp that makes a
# consumer unable to tell a list from a code ref, so it must not be what a
# LITERAL LIST carries.
subtest 'the list a map iterates is stamped List, not Unknown' => sub {
    my ( undef, $w, $err ) = run_and_translate(
        'my @m = map { $_ * 2 } (1,2); print "@m";', 'map-stamp' );
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;

    # The iterated list is what Count bounds: that is the loop's input, as
    # distinct from the empty ArrayLiteral seeding the accumulator.
    my ($count) = grep { ( $_->{op} // '' ) eq 'Count' } $ns->@*;
    ok $count, 'a Count bounds the loop' or return;
    my $input = $by{ ( $count->{inputs} // [] )->[0] // '' };
    ok $input, 'and it counts something' or return;

    is $input->{op}, 'ArrayLiteral', 'the counted value is the literal list';
    is $input->{stamp}, 'List', '... stamped List';
};

done_testing;
