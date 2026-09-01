# ABOUTME: substr takes 2, 3 or 4 arguments; a fixed pop_count of 2 silently
# ABOUTME: dropped the string being sliced and kept only index and length.

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

sub prog ( $w ) { return ( $w->{methods}{'main::__PROGRAM__'}{nodes} // [] ) }

# THE OPERAND COUNT IS NOT FIXED. substr is 2-, 3- or 4-argument, and OpMap
# declared a pop_count of 2 -- so a 3-arg call popped the INDEX and LENGTH and
# left the string on the stack:
#
#     substr("abcdef",1,3)   perl: bcd
#     graph: Call(substr) in=[Constant(1), Constant(3)]   -- no string
#
# A well-formed graph slicing nothing, with no diagnostic. The real arity is
# readable from the op: one kid per argument after the leading null.

subtest 'a 3-arg substr keeps all three operands' => sub {
    my ( $out, $w, $err ) = translate(
        'my $x = substr("abcdef",1,3); print $x;', 'substr3' );
    is $out, 'bcd', 'perl slices it' or return;
    ok $w, 'it translates' or do { diag($err); return };

    my ($call) = grep {
        ( $_->{op} // '' ) eq 'Call'
            && ( $_->{fields}{name} // '' ) eq 'substr'
    } prog($w)->@*;
    ok $call, 'a substr Call exists' or return;
    is scalar( ( $call->{inputs} // [] )->@* ), 3,
        'it takes three inputs -- string, offset, length';
};

subtest 'a 2-arg substr keeps both operands' => sub {
    my ( $out, $w, $err ) = translate(
        'my $x = substr("abcdef",2); print $x;', 'substr2' );
    is $out, 'cdef', 'perl slices to the end' or return;
    ok $w, 'it translates' or do { diag($err); return };

    my ($call) = grep {
        ( $_->{op} // '' ) eq 'Call'
            && ( $_->{fields}{name} // '' ) eq 'substr'
    } prog($w)->@*;
    ok $call, 'a substr Call exists' or return;
    is scalar( ( $call->{inputs} // [] )->@* ), 2,
        'it takes two inputs -- string and offset';
};

# THE s///e CASE THIS BLOCKS. A replacement whose value is a 3-arg substr left
# an extra value on the stack, so the handler refused it as "not a single
# value" -- a GAP whose real cause was the arity bug, one layer down.
subtest 'a substr replacement in s///e lowers' => sub {
    my ( $out, $w, $err ) = translate(
        'my $f = "not ok"; $f =~ s/^not /substr("abc",0,0)/e; print $f;',
        'substr-subst' );
    is $out, 'ok', 'perl substitutes the empty slice' or return;

    # `ok $w` IS NOT ENOUGH. B::SoN emits valid JSON with the program SKIPPED,
    # so a decoded document proves nothing -- the graph can be empty while the
    # test reads green. Assert the absence of the GAP and the presence of the
    # program's nodes.
    unlike $err, qr/GAP/, 'it does not GAP' or diag($err);
    ok scalar( prog($w // {})->@* ),
        '... and the program graph is present, not skipped';
};

done_testing;
