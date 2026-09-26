# ABOUTME: a map body calling a sub flattens whatever it returns; perl counts at
# ABOUTME: runtime, so the producer need not know the arity to describe it.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub write_tmp ($src, $tag) {
    my $f = "$dir/$tag." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    return $f;
}

sub emit ($src) {
    my $f = write_tmp( $src, 'g' );
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    my $data = eval { JSON::PP->new->decode($j) } or return ( undef, 'no graph' );
    unless ( $data->{methods}{'main::__PROGRAM__'} ) {
        my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
        $e =~ s/\n.*//s;
        return ( undef, $e );
    }
    my $out = eval { SoN::Deparse->new->render($data) };
    return ( undef, ( $@ || 'refused' ) ) unless defined $out;
    return ( $out, undef );
}

sub runs ($src) {
    my $f = write_tmp( $src, 'r' );
    my $o = qx($^X $f 2>&1);
    unlink $f;
    return $o;
}

# THE ARITY IS NOT IN THE PROGRAM, and it does not need to be. perl flattens a
# map body's contribution at RUNTIME -- it never counts at compile time either:
#
#     sub two { return (1, 2) }
#     map { two($_) } (0, 0)      4 elements
#     sub one { return 7 }
#     map { one($_) } (0, 0)      2 elements
#
# The producer refused both, because it desugars map into a loop with a
# ListAppend accumulator and could not say whether to append one value or N.
#
# BUT ListAppend ALREADY HANDLES UNKNOWN LENGTH. Measured, `map { @src } (0,0)`
# over a two-element @src emits
#
#     my @phi4_next = (@phi4, 1, 2);
#
# and prints 4 -- the aggregate flattens because the EMISSION defers to perl,
# exactly as the source did. A Call returning a list is the same shape, so the
# refusal was a property of the desugaring rather than of the program: a T1 GAP
# means "the program does not say", and here the program says precisely what
# perl acts on.

subtest 'a map body calling a list-returning sub' => sub {
    my $src = <<'SRC';
sub two { return (1, 2) }
my @r = map { two($_) } (0, 0);
print scalar(@r), " @r\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'four elements, flattened' or diag $out;
};

subtest 'a map body calling a scalar-returning sub' => sub {
    my $src = <<'SRC';
sub one { return 7 }
my @r = map { one($_) } (0, 0);
print scalar(@r), " @r\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'two elements' or diag $out;
};

# grep IS NOT map: its body is a PREDICATE and contributes the ELEMENT, not the
# body's value, so a list-returning call there must not flatten into the result.
subtest 'grep keeps its element, whatever the body returns' => sub {
    my $src = <<'SRC';
sub two { return (1, 2) }
my @r = grep { two($_) } (5, 6);
print scalar(@r), " @r\n";
SRC
    my ( $out, $why ) = emit($src);
    ok defined $out, 'renders' or do { diag $why; return };
    is runs($out), runs($src), 'two elements, the originals' or diag $out;
};

# THE KNOWN-ARITY PATHS MUST NOT CHANGE. A scalar builtin yields exactly one
# value and was already accepted by name; an aggregate body already flattened.
subtest 'the paths that already worked still work' => sub {
    for my $case (
        [ 'a scalar builtin', <<'SRC' ],
my @r = map { lc($_) } ("A", "B");
print scalar(@r), " @r\n";
SRC
        [ 'an aggregate body', <<'SRC' ],
my @src = (1, 2);
my @r = map { @src } (0, 0);
print scalar(@r), " @r\n";
SRC
    ) {
        my ( $name, $src ) = $case->@*;
        my ( $out, $why ) = emit($src);
        ok defined $out, "$name renders" or do { diag $why; next };
        is runs($out), runs($src), "$name round-trips" or diag $out;
    }
};

done_testing;
