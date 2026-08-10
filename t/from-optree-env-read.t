# ABOUTME: Tests SoN::FromOptree translates $ENV{KEY} to an EnvRead node.
# ABOUTME: gv[*ENV] -> rv2hv -> helem(const key) => EnvRead(key: KEY) :Str, not a Subscript.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# Per corpus/mdtest/host.md H3: $ENV{KEY} is an EnvRead node lowering to the
# host C getenv, NOT a generic hash Subscript over a stash-name Constant.

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub node_of ($g, $want_op) {
    my ($node) = grep { $_->operation eq $want_op } $g->nodes->@*;
    return $node;
}

subtest '$ENV{KEY} is an EnvRead node carrying the key (H3)' => sub {
    my $g = graph_of('sub { $ENV{CHALK_G7_TEST} }');
    my $env = node_of($g, 'EnvRead');
    ok(defined $env, 'has an EnvRead node') or return;
    is($env->key, 'CHALK_G7_TEST', 'carries the env-var key');
    is($env->stamp->type, 'Str', 'EnvRead is stamped Str');
    ok(!defined node_of($g, 'Subscript'),
        'no generic Subscript emitted for the %ENV read');
};

subtest 'a non-ENV hash read stays a Subscript (teeth)' => sub {
    # A read of a genuine hash (a real container, not %ENV) must NOT become an
    # EnvRead -- only the %ENV stash triggers it.
    my $g = graph_of('sub { my %h = (a => 1); $h{a} }');
    ok(!defined node_of($g, 'EnvRead'),
        'a lexical %h read is not an EnvRead');
};

subtest 'a package hash %Foo::ENV is NOT an EnvRead (stash teeth)' => sub {
    # The bare gv NAME "ENV" is ambiguous: %Foo::ENV shares it with the real
    # environment %main::ENV. Only main::ENV is the process environment; a
    # package hash whose short name is ENV must never become getenv("PATH").
    #
    # It is now refused in the PRODUCER as an unmodeled package aggregate. It
    # previously became a generic Subscript over the stash-NAME Constant, which
    # the backend then refused anyway ("Subscript container has repr=Str") --
    # the same refusal, one layer later. Letting that name string into the
    # graph is what made `$#x` compute length("x"), so it is stopped at source.
    my $err = dies { graph_of('sub { $Foo::ENV{PATH} }') };
    like($err, qr/GAP:/, '%Foo::ENV read is refused, not silently mishandled');
    like($err, qr{package array/hash},
        '... named as an unmodeled package aggregate');
    unlike($err // '', qr/EnvRead|getenv/,
        '... and never mistaken for the process environment');
};

subtest '%ENV read from inside another package still resolves (main::ENV)' => sub {
    # %ENV is always main::ENV regardless of the reading package, so a read from
    # package Acme must still be recognised as the environment.
    my $g = graph_of('package Acme; sub { $ENV{CHALK_G7_TEST} }');
    my $env = node_of($g, 'EnvRead');
    ok(defined $env, 'main::ENV read from package Acme is still an EnvRead')
        or return;
    is($env->key, 'CHALK_G7_TEST', 'carries the key');
};

done_testing();
