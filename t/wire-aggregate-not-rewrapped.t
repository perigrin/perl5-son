# ABOUTME: Assigning an already-aggregate value to an array must not re-wrap it.
# ABOUTME: ArrayLiteral[Array] has one INPUT but two ELEMENTS -- Count would read 1.
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

# A LIST IS NOT AN ARRAY, and the array-assignment path wraps each popped RHS
# value as one ELEMENT: `my @a = (1,2,3)` correctly builds ArrayLiteral with
# three inputs, and Count reads 3.
#
# But when the RHS is a SINGLE value that is ALREADY an aggregate -- what
# `grep`/`map` produce, an accumulated Array -- wrapping it makes
# ArrayLiteral[Array]: ONE input holding TWO elements. A consumer counting
# inputs reads 1 where perl says 2. That is a silent wrong answer, which is the
# outcome the refuse-or-lower contract exists to prevent, so the wrap must not
# happen when the value is already the aggregate being assigned.
subtest 'an aggregate RHS is assigned directly, not wrapped as one element' => sub {
    my ( $w, $err ) = translate(
        'my @g = grep { $_ > 1 } (1,2,3); print scalar(@g);', 'agg-rhs' );
    ok $w, 'it translates' or diag($err), return;

    my $all = nodes($w);
    my %by_id = map { $_->{id} => $_ } $all->@*;

    # Whatever Count feeds scalar(@g) must count the ACCUMULATOR, not a
    # one-input wrapper around it.
    my ($count) = grep { ( $_->{op} // '' ) eq 'Count' } $all->@*;
    ok $count, 'a Count computes scalar(@g)' or return;

    my $counted = $by_id{ $count->{inputs}[0] };
    isnt $counted->{op}, 'ArrayLiteral',
        'Count does not read a re-wrapped ArrayLiteral'
        or diag("Count reads $counted->{op} with "
              . scalar( $counted->{inputs}->@* ) . ' input(s)');
};

# The ordinary list assignment must keep wrapping: this is the case the wrap
# exists for, and a fix that skipped it everywhere would break it.
subtest 'a plain list RHS is still wrapped element-wise' => sub {
    my ( $w, $err ) = translate( 'my @a = (1,2,3); print scalar(@a);', 'list-rhs' );
    ok $w, 'it translates' or diag($err), return;

    my $all = nodes($w);
    my %by_id = map { $_->{id} => $_ } $all->@*;
    my ($count) = grep { ( $_->{op} // '' ) eq 'Count' } $all->@*;
    ok $count, 'a Count computes scalar(@a)' or return;

    my $counted = $by_id{ $count->{inputs}[0] };
    is $counted->{op}, 'ArrayLiteral', 'it counts an ArrayLiteral';
    is scalar( $counted->{inputs}->@* ), 3, '... with one input per element';
};

done_testing;
