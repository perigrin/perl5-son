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
    # package hash whose short name is ENV must stay a plain hash read, or
    # $Foo::ENV{PATH} would miscompile into getenv("PATH").
    my $g = graph_of('sub { $Foo::ENV{PATH} }');
    ok(!defined node_of($g, 'EnvRead'),
        '%Foo::ENV read is NOT an EnvRead (getenv miscompile avoided)');
    ok(defined node_of($g, 'Subscript'),
        'it stays a generic hash Subscript');
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
