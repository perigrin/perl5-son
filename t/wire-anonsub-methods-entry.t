# ABOUTME: A non-capturing anon sub's body becomes its own `methods` entry, and
# ABOUTME: the AnonSub node names it -- the same shape a named sub already uses.

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
    my $err  = do { open my $e, '<', "$dir/$name.err" or return ''; local $/; <$e> } // '';
    return ( $out, ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

# (a), NOT an inline nested graph. chalk's loader has no AnonSub emit or load
# arm at all, so an inline graph would be silently dropped by its generic
# field path and arrive as graph=undef -- the same silent-drop failure the
# `want` field hit. A `methods` entry is the path that already works.
subtest 'a non-capturing anon sub body becomes a methods entry' => sub {
    my ( $out, $w, $err ) = run_and_translate(
        'my $c = sub { 42 }; print $c->();', 'anon-basic' );
    is $out, '42', 'perl calls it' or return;
    ok $w, 'it translates rather than GAPping' or do { diag($err); return };

    my %methods = ( $w->{methods} // {} )->%*;
    my @anon = grep { /__ANON__/ } sort keys %methods;
    is scalar(@anon), 1, 'exactly one anon body was emitted' or return;

    my $body = $w->{methods}{ $anon[0] }{nodes} // [];
    ok scalar($body->@*), 'the anon body has nodes -- it was not dropped';

    # The body must be the SUB'S, not the program's: 42 lives in it.
    ok scalar( grep {
        ( $_->{op} // '' ) eq 'Constant'
            && ( $_->{fields}{value} // '' ) eq '42'
    } $body->@* ), '... and contains the body constant';
};

# THE CALL MUST NAME THE BODY. Shipping `Call(name="unknown")` while the body
# sits in `methods` unreferenced is the silent wrong answer the original
# refusal existed to prevent -- worse than the old GAP, because the graph now
# looks complete.
#
# The AnonSub node itself is CONSUMED by the call rather than persisting: it is
# not a value anything holds. Asserting the node survives would pin an
# implementation detail and fail for the right behaviour.
subtest 'calling an anon sub names its methods entry' => sub {
    for my $case (
        [ 'my $c = sub { 42 }; print $c->();', 'via-pad' ],
        [ 'print sub { 42 }->();',             'direct' ],
    ) {
        my ( $src, $label ) = $case->@*;
        my ( $out, $w, $err ) = run_and_translate( $src, "anon-names-$label" );
        is $out, '42', "perl calls it ($label)";
        ok $w, "it translates ($label)" or do { diag($err); next };

        my ($call) = grep { ( $_->{op} // '' ) eq 'Call' }
            ( $w->{methods}{'main::__PROGRAM__'}{nodes} // [] )->@*;
        ok $call, "the program has a Call ($label)" or next;

        my $name = $call->{fields}{name} // '';
        isnt $name, 'unknown',
            "the callee is named, not 'unknown' ($label)";
        ok exists $w->{methods}{$name},
            "... and that name IS a methods key, not dangling ($label)";
    }
};

# TWO ANON SUBS IN DIFFERENT SUBS SHARE A PAD SLOT. `targ` is a pad index
# scoped to its enclosing CV, so `sub f { sub {1} }` and `sub g { sub {2} }`
# both report targ=2. A methods key built from targ alone silently loses one
# body to the other, because it is a hash key.
subtest 'anon subs in different subs get distinct names' => sub {
    my ( undef, $w, $err ) = run_and_translate(
        'sub f { my $c = sub { 1 }; $c->() } '
      . 'sub g { my $c = sub { 2 }; $c->() } '
      . 'print f() + g();', 'anon-collide' );
    ok $w, 'it translates' or do { diag($err); return };

    my %methods = ( $w->{methods} // {} )->%*;
    my @anon = grep { /__ANON__/ } sort keys %methods;
    is scalar(@anon), 2,
        'both anon bodies survive -- neither overwrote the other';
};

# A CAPTURING ANON SUB STILL REFUSES. The slice is deliberately partial, and a
# fix that lowered captures by ignoring them would be the silent wrong answer
# this whole contract exists to prevent.
subtest 'a capturing anon sub still refuses' => sub {
    my ( undef, $w, $err ) = run_and_translate(
        'my $x = 5; my $c = sub { $x }; print $c->();', 'anon-capture' );
    like $err, qr/GAP.*closing over.*\$x/,
        'it refuses, naming the captured variable';
};

done_testing;
