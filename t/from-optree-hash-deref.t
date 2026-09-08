# ABOUTME: `%$h` / `$h->%*` flattens a literal hash-ref into its pairs,
# ABOUTME: exactly as the array side already does for `@$r` / `$r->@*`.
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

# THE DEFECT, reported by chalk against corpus F21. `my %c = $h->%*` built
#
#     HashLiteral  inputs=2  :HashRef    <- {a=>1}, correct
#     HashLiteral  inputs=1  :Hash       <- the deref
#
# A hash literal's inputs are 2N alternating keys and values, so a consumer
# computing a pair count from the second node gets 0.5. It is a HashLiteral
# whose single input is the thing being DEREFERENCED -- the same class of
# defect as the ArrayRef name: a node standing in for something it is not.
#
# The array side already gets this right. rv2av in list context flattens a
# literal referent into its elements -- `my @c = $r->@*` gives
# ArrayLiteral(in=2, Array) -- and GAPs loudly on a runtime ref it cannot
# statically flatten. rv2hv had no such handler, so the deref fell through to
# the list-assign path and was wrapped as a one-input container.
subtest 'a literal hash-ref deref flattens to its pairs' => sub {
    my ( $w, $err ) = translate(
        'my $h = {a=>1}; my %c = $h->%*; print $c{a};', 'hash-deref' );
    ok $w, 'it translates' or diag($err), return;

    my @hl = grep { ( $_->{op} // '' ) eq 'HashLiteral' } nodes($w)->@*;
    ok scalar(@hl), 'HashLiteral nodes exist' or return;

    is scalar( grep { scalar( ( $_->{inputs} // [] )->@* ) % 2 } @hl ), 0,
        'every HashLiteral has an EVEN input count -- they are key/value pairs';
};

# THE ARRAY SIDE IS THE MODEL, and the property that matters is that the
# assigned array has the REFERENT's length rather than wrapping the ref as one
# element. It no longer materialises an ArrayLiteral of flattened elements: a
# deref is a memory READ (PostfixDeref), because substituting the literal's
# construction-time values loses any mutation before the deref. See
# t/from-optree-deref-is-a-memory-read.t.
subtest 'the array deref counts the referent, not the ref' => sub {
    my ( $w, $err ) = translate(
        'my $r = [1,2]; my @c = $r->@*; print scalar(@c);', 'array-deref' );
    ok $w, 'it translates' or diag($err), return;

    my $n = nodes($w);
    my %by = map { $_->{id} => $_ } $n->@*;

    my ($deref) = grep { ( $_->{op} // '' ) eq 'PostfixDeref' } $n->@*;
    ok $deref, 'the deref is a PostfixDeref' or return;
    is $deref->{stamp}, 'Array', '... stamped Array, the container kind';

    my ($count) = grep { ( $_->{op} // '' ) eq 'Count' } $n->@*;
    ok $count, 'scalar(@c) is a Count' or return;
    is $by{ $count->{inputs}[0] }{op}, 'PostfixDeref',
        'and it counts the DEREF -- the referent, not the single ref';
};

# A RUNTIME REF IS THE SAME READ, not a different problem: it refused for being
# unflattenable, and a read needs no compile-time contents.
subtest 'a runtime hash-ref deref lowers' => sub {
    my ( $w, $err ) = translate(
        'sub f { my ($h) = @_; my %c = %$h; return $c{a} } print f({a=>1});',
        'runtime-deref' );
    unlike $err, qr/GAP:/, 'not refused' or diag $err;
    ok $w, 'it translates' or return;

    my ($deref) = grep { ( $_->{op} // '' ) eq 'PostfixDeref' }
                  ( $w->{methods}{'main::f'}{nodes} // [] )->@*;
    ok $deref, 'the deref is a PostfixDeref' or return;
    is $deref->{fields}{sigil}, '%', '... carrying the hash sigil';
};

done_testing;
