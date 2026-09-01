# ABOUTME: `sub { ... }` must never leave a Call naming "unknown": a
# ABOUTME: non-capturing one lowers to its own graph, a capturing one refuses.
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
# NOW LOWERED for the non-capturing case: the body becomes its own `methods`
# entry under a per-site name and the Call names it. What must never come back
# is the shape above -- a graph that looks complete with the body gone.
subtest 'an anonymous sub is lowered, not dropped' => sub {
    my ( $w, $err ) = translate(
        'my $c = sub { 42 }; print $c->();', 'anon-call' );
    ok $w, 'it translates' or do { diag($err); return };

    my ($call) = grep { ( $_->{op} // '' ) eq 'Call' }
        ( $w->{methods}{'main::__PROGRAM__'}{nodes} // [] )->@*;
    ok $call, 'the program calls something' or return;
    isnt $call->{fields}{name} // '', 'unknown',
        'the callee is NOT named "unknown"';
    ok exists $w->{methods}{ $call->{fields}{name} // '' },
        '... and its body is present under that name';
};

# A CALLBACK ARGUMENT STILL REFUSES, and that is the correct answer today.
# `apply(sub { 7 })` passes the anon sub as an ARGUMENT: the entersub that
# follows calls `apply`, not the anon sub, so nothing on the wire would name
# the body. Lowering it emits a graph whose body is unreachable -- the same
# defect as a Call to "unknown", which is what this file exists to forbid.
#
# The value side needs a node carrying the name before this can lower.
# A CALLBACK ARGUMENT LOWERS: the AnonSub node rides as an input to the Call,
# so the body IS named even though no Call names it directly. That the callee
# then calls it through a parameter (`$f->()` -> Call name="unknown") is a
# separate, PRE-EXISTING limitation -- `apply(\&named_sub)` produces the same
# unknown, so it is nothing to do with anonymity.
subtest 'an anonymous sub passed as a callback is lowered and named' => sub {
    my ( $w, $err ) = translate(
        'sub apply { my $f = shift; $f->() } print apply(sub { 7 });',
        'anon-callback' );
    ok $w, 'it translates' or do { diag($err); return };

    my %methods = ( $w->{methods} // {} )->%*;
    my @anon = grep { /__ANON__/ } keys %methods;
    is scalar(@anon), 1, 'the body reached the wire' or return;

    # It must be NAMED by something -- here an AnonSub node passed as an
    # argument, not a Call. A body nothing names is the defect this file
    # forbids, whichever node does the naming.
    my %named;
    for my $mm ( keys %methods ) {
        for my $n ( ( $methods{$mm}{nodes} // [] )->@* ) {
            my $nm = $n->{fields}{name};
            $named{$nm} = 1 if defined $nm;
        }
    }
    ok $named{ $anon[0] }, '... and something names it';
};

# A BODY NOTHING CAN NAME REFUSES, and takes its enclosing graph with it.
# Shipping the enclosing graph would leave a Call to "unknown" pointing at a
# body that is not there -- worse than the refusal, because it looks complete.
subtest 'an unnameable anon sub refuses, emitting nothing' => sub {
    my ( $w, $err ) = translate(
        'my @subs = (sub { 1 }, sub { 2 }); print $subs[0]->() + $subs[1]->();',
        'anon-orphan' );
    like $err, qr/GAP/, 'it refuses';
    my %methods = ( ( $w // {} )->{methods} // {} )->%*;
    is scalar( grep { /__ANON__/ } keys %methods ), 0,
        '... and emits no orphan body';
};

# A CAPTURING ONE STILL REFUSES. The slice is deliberately partial: a per-site
# name is only correct where the site IS the identity, which capture breaks
# (three closures over three values would share one name).
subtest 'a capturing anonymous sub still refuses' => sub {
    my ( undef, $err ) = translate(
        'my $x = 5; my $c = sub { $x }; print $c->();', 'anon-capture' );
    like $err, qr/GAP:.*closing over.*\$x/,
        'refused, naming the captured variable';
};

# A NAMED SUB IS UNCHANGED -- it already becomes its own graph in `methods`,
# referenced by a Call carrying the graph name -- the convention an anon sub
# now follows too.
subtest 'a named sub still becomes its own graph' => sub {
    my ( $w, $err ) = translate( 'sub f { 42 } print f();', 'named' );
    ok $w, 'it translates' or diag($err), return;
    ok exists( ( $w->{methods} // {} )->{'main::f'} ),
        'the body is its own graph, keyed by name';
};

done_testing;
