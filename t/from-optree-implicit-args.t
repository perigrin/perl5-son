# ABOUTME: Tests SoN::FromOptree modeling of the implicit @_ argument array.
# ABOUTME: Covers bare shift/pop and list-assignment from @_ (my ($x) = @_).

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;

# Both idioms read the implicit @_ argument array, which the optree does NOT
# spell out: bare `shift` is a nullary op (the @_ operand is implied), and
# `my ($x) = @_` has its rv2av(gv[*_]) RHS elided by the padrange optimization.
# @_ must be modeled as a real array source (an ArgsSource node), not dropped.
# It rode on StashAccess(main,'_') until the node split -- StashAccess's job is
# the ENTRY DEFINITION, and an argument list is not that.
# or turned into a string Constant.

sub ops_of ($coderef) {
    my $graph = SoN::FromOptree->translate($coderef);
    return [ map { $_->operation } $graph->nodes->@* ];
}

sub graph_of ($coderef) {
    return SoN::FromOptree->translate($coderef);
}

subtest 'bare shift reads implicit @_' => sub {
    my $g = graph_of(sub { my $x = shift; return $x; });
    ok(defined $g, 'translate did not die on bare shift');

    my @ops = map { $_->operation } $g->nodes->@*;
    ok((grep { $_ eq 'Call' } @ops), 'shift lowers to a Call');

    # The @_ operand must be a real array source, not a bogus Constant.
    my @args_sources = grep {
        $_->operation eq 'ArgsSource'
    } $g->nodes->@*;
    ok(@args_sources, 'shift operand is an ArgsSource, not a Constant');
};

subtest 'bare pop reads implicit @_' => sub {
    my $g = graph_of(sub { my $x = pop; return $x; });
    ok(defined $g, 'translate did not die on bare pop');
    my @args_sources = grep {
        $_->operation eq 'ArgsSource'
    } $g->nodes->@*;
    ok(@args_sources, 'pop operand is an ArgsSource');
};

subtest 'list-assignment from @_ (single)' => sub {
    # F3 corpus idiom: sub add1 { my ($x) = @_; return $x + 1 }
    my $g = graph_of(sub { my ($x) = @_; return $x + 1; });
    ok(defined $g, 'translate did not die on my ($x) = @_');

    my @ops = map { $_->operation } $g->nodes->@*;
    ok((grep { $_ eq 'Add' } @ops), 'body Add survives the @_ binding');
    ok((grep { $_ eq 'VarDecl' } @ops), 'the lexical $x is declared');
};

subtest 'list-assignment from @_ (multiple)' => sub {
    my $g = graph_of(sub { my ($p, $q) = @_; return $p; });
    ok(defined $g, 'translate did not die on my ($p, $q) = @_');
};

done_testing();
