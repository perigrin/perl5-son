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

done_testing;
