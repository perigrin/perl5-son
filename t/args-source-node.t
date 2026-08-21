# ABOUTME: `@_` is an ArgsSource node, not a StashAccess entry definition.
# ABOUTME: The two are different jobs: an argument list vs a name defined outside.
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

sub ops_of ($wire, $graph) {
    return map { $_->{op} // '' } nodes_of($wire, $graph);
}

# `@_` is the ARGUMENT LIST: created by the caller, scoped to the innermost
# enclosing sub call. `StashAccess`'s remaining job is the ENTRY DEFINITION --
# naming a value defined OUTSIDE this unit, with no value of its own.
#
# Those are different jobs. Riding both on one node is what let `$_` and `@_`
# hash-cons into a single node; the sigil closed that hazard, but the conflation
# is still there and it blocks renaming StashAccess to EntryDef (it would not
# mean one thing).
subtest '@_ is an ArgsSource, not a StashAccess' => sub {
    my $wire = wire_for('sub f { my $n = shift; $n + 1 } print f(41), "\n";', 'shift');
    my @ops = ops_of($wire, 'main::f');

    ok scalar(grep { $_ eq 'ArgsSource' } @ops),
        '@_ is an ArgsSource node' or diag "ops: @ops";
    ok !scalar(grep { $_ eq 'StashAccess' } @ops),
        'and NOT a StashAccess' or diag "ops: @ops";
};

# `$_[0]` reaches the same array, so it must reach the same node kind.
subtest '$_[N] reads the same ArgsSource' => sub {
    my $wire = wire_for('sub f { $_[0] + 1 } print f(41), "\n";', 'positional');
    my @ops  = ops_of($wire, 'main::f');
    ok scalar(grep { $_ eq 'ArgsSource' } @ops),
        '$_[0] reads an ArgsSource' or diag "ops: @ops";
};

# THE BILATERAL PARTNER, and the reason this is not just a rename: a scalar
# `$_` must NOT become an ArgsSource. It is a different variable.
subtest '$_ does not become an ArgsSource' => sub {
    my $wire = wire_for('sub f { /x/ ? 1 : 0 } $_ = "x"; print f(), "\n";', 'underscore');
    my @ops  = ops_of($wire, 'main::f');
    ok !scalar(grep { $_ eq 'ArgsSource' } @ops),
        '$_ is not an ArgsSource' or diag "ops: @ops";
};

# And the OTHER remaining role stays put: a package variable read before any
# write in this unit is an entry definition, and still a StashAccess until
# step 4 renames it.
subtest 'an entry definition is still a StashAccess' => sub {
    my $wire = wire_for('our $g; print $g // "u", "\n";', 'entrydef');
    my @ops  = ops_of($wire, 'main::__PROGRAM__');
    ok scalar(grep { $_ eq 'StashAccess' } @ops),
        'an unwritten package read is a StashAccess' or diag "ops: @ops";
    ok !scalar(grep { $_ eq 'ArgsSource' } @ops),
        'and not an ArgsSource';
};

done_testing;
