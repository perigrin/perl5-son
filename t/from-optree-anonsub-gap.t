# ABOUTME: `sub { ... }` must refuse -- its body is not lowered, and shipping
# ABOUTME: a Call to "unknown" is a silent wrong answer.
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

# THE DEFECT, found while answering chalk's question about how a map/grep block
# should reach the wire. `sub { 42 }` was dropped SILENTLY:
#
#     my $c = sub { 42 }; print $c->();
#       perl prints 42
#       graph:  Constant(undef), Call(dispatch_kind=direct, name="unknown")
#       stderr: "syntax OK"
#
# The body is gone, the callee is literally named "unknown", and nothing says
# so. That is the same silent-drop class as map/grep (1d470a9), one construct
# over -- and worse, because a callback passed to a function is ordinary perl:
# `apply(sub { 7 })` was equally silent.
#
# AnonSub is dead vocabulary today: the node class exists, OpMap maps anoncode
# to it, and FromOptree builds it ZERO times.
subtest 'an anonymous sub refuses rather than dropping its body' => sub {
    my ( undef, $err ) = translate(
        'my $c = sub { 42 }; print $c->();', 'anon-call' );
    like $err, qr/GAP:/, 'refused';
    like $err, qr/anonymous sub|sub \{/, '... naming the construct';
};

subtest 'an anonymous sub passed as a callback refuses' => sub {
    my ( undef, $err ) = translate(
        'sub apply { my $f = shift; $f->() } print apply(sub { 7 });',
        'anon-callback' );
    like $err, qr/GAP:/, 'refused';
};

# A NAMED SUB IS UNCHANGED -- it already becomes its own graph in `methods`,
# referenced by a Call carrying the graph name, and that is the convention an
# anon sub should eventually follow.
subtest 'a named sub still becomes its own graph' => sub {
    my ( $w, $err ) = translate( 'sub f { 42 } print f();', 'named' );
    ok $w, 'it translates' or diag($err), return;
    ok exists( ( $w->{methods} // {} )->{'main::f'} ),
        'the body is its own graph, keyed by name';
};

done_testing;
