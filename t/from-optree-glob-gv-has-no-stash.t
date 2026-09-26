# ABOUTME: `glob` carries a placeholder gv[*<none>::] with no stash, so a
# ABOUTME: STASH->NAME read on it crashes rather than refusing or lowering.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir( CLEANUP => 1 );

sub graph_of ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
    unlink $f;
    return ( eval { JSON::PP->new->decode($j) }, $e );
}

# THE OPTREE CARRIES A PLACEHOLDER. Measured:
#
#     my @n = glob("*.xyz");
#       5  <#> gv[*<none>::] s
#       6  <@> glob[t3] lK/1
#
# `glob` is a named unary whose gv slot holds `*<none>::` -- a GV with NO
# STASH. The gv handler read `$gv->STASH->NAME` behind an `if ($gv)` guard
# that only checks truthiness, so the read reached a B::SPECIAL and died:
#
#     INTERNAL ERROR translating main::__PROGRAM__ (masked as a silent skip
#     -- fix or convert to a clean GAP): Can't locate object method "NAME"
#     via package "B::SPECIAL" at lib/SoN/FromOptree.pm line 4254
#
# An INTERNAL ERROR is masked as a silent skip, so the program emitted
# `{"methods":{}}` -- no graph, no GAP, and a census that reads GAP counts
# scored it CLEAN. That is the worst outcome in this project's ranking: a
# silent drop wearing a clean result. [[crashes-mask-gaps]].
subtest 'a glob does not crash the walker' => sub {
    my ( $data, $err ) = graph_of('my @n = glob("*.xyz"); print scalar(@n), "\n";');
    unlike $err, qr/INTERNAL ERROR/, 'no internal error'
        or diag($err);
    ok $data, 'JSON came back';
    ok $data && keys %{ $data->{methods} // {} },
        'the graph is not empty' or diag($err);
};

# THE ANGLE-BRACKET SPELLING is the same op and must behave the same way.
subtest 'the <*.glob> spelling does not crash either' => sub {
    my ( $data, $err ) = graph_of('my @n = <*.xyz>; print scalar(@n), "\n";');
    unlike $err, qr/INTERNAL ERROR/, 'no internal error'
        or diag($err);
    ok $data && keys %{ $data->{methods} // {} }, 'the graph is not empty';
};

# A REAL PACKAGE GV MUST STILL RESOLVE -- the guard must narrow to "has a
# stash", not to "is not a glob op", or every package read loses its name.
subtest 'a package scalar still resolves its name' => sub {
    my ( $data, $err ) = graph_of('our $pkg = 7; print "$pkg\n";');
    unlike $err, qr/INTERNAL ERROR/, 'no internal error';
    my @nodes = map { $_->{nodes}->@* } values %{ $data->{methods} // {} };
    ok scalar(@nodes), 'nodes exist';
};

# AND THE %ENV PATH MUST SURVIVE. The STASH read exists to disambiguate
# main::ENV from a package hash whose short name is also ENV, so a guard that
# skipped the read entirely would break that disambiguation.
#
# A read of the process environment does NOT carry `main::ENV` as a symbol --
# measured, it lowers to a dedicated `EnvRead` node with a `key` field, and the
# qualified name exists only inside the walker to route it there. An earlier
# draft of this subtest asserted the symbol was on the wire and failed for that
# reason rather than for a defect.
subtest 'an %ENV read still reaches EnvRead' => sub {
    my ( $data, $err ) = graph_of('print $ENV{PATH} ? "y\n" : "n\n";');
    unlike $err, qr/INTERNAL ERROR/, 'no internal error';
    my @nodes = map { $_->{nodes}->@* } values %{ $data->{methods} // {} };
    my ($env) = grep { $_->{op} eq 'EnvRead' } @nodes;
    ok $env, 'an EnvRead node exists' or return;
    is( ( $env->{fields} // {} )->{key}, 'PATH', '... keyed on PATH' );
};

# THE PATTERN IS THE FIRST OPERAND, NOT THE PLACEHOLDER. Measured, glob
# pushes TWO things:
#
#     4  <$> const[PV "*.xyz"] s      the pattern
#     5  <#> gv[*<none>::] s          the placeholder
#     6  <@> glob[t3] lK/1
#
# The walker consumed the gv (which the fix above turns into an empty-named
# Constant) and left the pattern loose on the stack, so the graph read
#
#     4 Call glob in=[3]        <- the EMPTY constant, not the pattern
#     5 ArrayLiteral in=[2,4]   <- the pattern AND the call, two elements
#
# and `scalar(@n)` came out 1 where perl says 0: the list held the pattern
# string itself plus the call's result.
subtest 'glob takes its pattern, and an empty match counts 0' => sub {
    my ( $data, $err ) = graph_of(
        'my @n = glob("*.nonexistent-xyz"); print scalar(@n), "\n";' );
    unlike $err, qr/INTERNAL ERROR|GAP/, 'no error' or diag($err);
    my @nodes = map { $_->{nodes}->@* } values %{ $data->{methods} // {} };
    my ($call) = grep {
        $_->{op} eq 'Call'
            && ( ( $_->{fields} // {} )->{name} // '' ) eq 'glob'
    } @nodes;
    ok $call, 'a glob Call exists' or return;

    my %by_id = map { $_->{id} => $_ } @nodes;
    my @args  = map { $by_id{$_} } ( $call->{inputs} // [] )->@*;
    my ($pat) = grep {
        ( ( $_->{fields} // {} )->{value} // '' ) eq '*.nonexistent-xyz'
    } @args;
    ok $pat, 'the PATTERN is an operand of the Call, not left loose';
};

done_testing;
