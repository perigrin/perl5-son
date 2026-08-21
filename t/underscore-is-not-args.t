# ABOUTME: `$_` and `@_` are different variables and must not share an IR node.
# ABOUTME: Both were keyed `main::_`, so an unbound $_ match hash-consed onto @_.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire_for ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings 'uninitialized';\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

sub nodes_of ($wire, $graph) {
    return @{ ($wire->{methods}{$graph} // {})->{nodes} // [] };
}

# THE COLLISION. `$_` and `@_` are different variables that happen to share the
# glob name `_`. The producer keyed BOTH as `main::_` in the scope map, so in a
# sub using `shift @_` AND an unbound `/re/` match they hash-consed into ONE
# node -- measured: a single StashAccess(_) feeding both the shift Call and the
# RegexMatch.
#
# That is a wrong graph regardless of what the backend then does with it: one
# node cannot be two variables. It surfaces today as a GAP whose message names
# the wrong cause ("a list assignment `my (...) = @_`", of which the source has
# none), because the backend sees a non-shift consumer on the @_ node.
subtest 'an unbound $_ match does not share a node with @_' => sub {
    my $wire = wire_for(
        'sub f { my $n = shift; my $m = /x/ ? 1 : 0; $n + $m } print f(41), "\n";',
        'collide');
    my @n = nodes_of($wire, 'main::f');

    # `@_` is now its own NODE KIND, which is a stronger separation than the
    # sigil that first fixed this: the two cannot share identity even in
    # principle. (The sigil still matters for $g vs @g, and for StashAccess's
    # remaining entry-definition role.)
    my %args_id = map  { ($_->{id} // '') => 1 }
                  grep { ($_->{op} // '') eq 'ArgsSource' } @n;

    my ($shift) = grep {
        ($_->{op} // '') eq 'Call' && (($_->{fields}{name} // '') eq 'shift')
    } @n;
    ok $shift, 'the sub has a shift @_' or return;
    ok scalar(grep { $args_id{$_} } @{ $shift->{inputs} // [] }),
        'the shift reads the ArgsSource node';

    my ($match) = grep { ($_->{op} // '') eq 'RegexMatch' } @n;
    ok $match, 'the sub has a RegexMatch' or return;

    # THE COLLISION: the $_ match subject must not BE the @_ node.
    my @shared = grep { $args_id{$_} } @{ $match->{inputs} // [] };
    is_deeply \@shared, [],
        'the $_ match subject is not the @_ node'
        or diag "shared node ids: @shared";
};

# The bilateral partner: a sub using ONLY @_ still gets its argument source, so
# a fix cannot simply stop building the node.
subtest '@_ still resolves on its own' => sub {
    my $wire = wire_for('sub f { my $n = shift; $n + 1 } print f(41), "\n";', 'argsonly');
    my @n = nodes_of($wire, 'main::f');
    my ($shift) = grep {
        ($_->{op} // '') eq 'Call' && (($_->{fields}{name} // '') eq 'shift')
    } @n;
    ok $shift, 'the shift Call is present' or return;
    # wire inputs are plain node ids, not hashrefs
    my @operands = grep { defined } @{ $shift->{inputs} // [] };
    ok scalar @operands, 'and it still has an @_ operand'
        or diag 'shift has no operand';
};

# And the other direction: a sub using ONLY $_ must still reach $_.
subtest '$_ still resolves on its own' => sub {
    my $wire = wire_for('sub f { /x/ ? 1 : 0 } $_ = "x"; print f(), "\n";', 'usonly');
    my @n = nodes_of($wire, 'main::f');
    my ($match) = grep { ($_->{op} // '') eq 'RegexMatch' } @n;
    ok $match, 'the match is present' or return;
    my @subject = grep { defined } @{ $match->{inputs} // [] };
    ok scalar @subject, 'and it still has a subject'
        or diag 'match has no subject';
};

# THE GENERAL RULE, not just the `_` case. `$g` and `@g` are unrelated
# variables in one stash. The first version of this fix sigil-qualified all
# five scope KEYS but stamped the sigil on only two of four CONSTRUCTION
# sites, so the key said '@' while the node defaulted to '$' -- and the nodes
# hash-consed anyway. Measured then: DISTINCT=1 where 2 was required.
#
# A key and a hash are two different things; qualifying one does not qualify
# the other. This asserts the NODES, which is where the identity lives.
subtest '$g and @g are different nodes' => sub {
    require SoN::FromOptree;
    require SoN::OptSuppress;
    SoN::OptSuppress::suppress_peep();
    my $cv = eval 'sub { my $s = $main::g; my $n = scalar @main::g; $s . $n }';
    SoN::OptSuppress::restore_peep();
    ok $cv, 'compiled' or return;

    my $graph = eval { SoN::FromOptree->translate($cv) };
    ok $graph, 'translated' or do { diag $@; return };

    my @stash = grep { $_->operation eq 'StashAccess' } @{ $graph->nodes };
    my %by_sigil = map { $_->sigil => 1 } @stash;
    is scalar(@stash), 2, 'two distinct StashAccess nodes for one name'
        or diag join ', ', map { $_->sigil . $_->var_name } @stash;
    ok $by_sigil{'$'}, 'one carries the scalar sigil';
    ok $by_sigil{'@'}, 'the other carries the array sigil';
};

done_testing;
