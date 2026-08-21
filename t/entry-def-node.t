# ABOUTME: A value defined outside this unit is an EntryDef, not a "StashAccess".
# ABOUTME: The node names an incoming value; it is not a symbol-table lookup.
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

sub ops_of ($wire, $graph) {
    return map { $_->{op} // '' } @{ ($wire->{methods}{$graph} // {})->{nodes} // [] };
}

# The node's one remaining job is naming a value DEFINED OUTSIDE this unit --
# an SSA entry definition, the same idea as a Phi argument at a block boundary
# lifted to the unit boundary.
#
# "StashAccess" said something different and wrong: a symbol-table LOOKUP. That
# reading is why the node accumulated roles -- anything needing a global reached
# for the node whose name matched, which is how `@_` ended up on it. It also
# frames the wrong question for a separately-compiled unit, where the entry
# definition is exactly what a caller must supply.
subtest 'an unwritten package variable read is an EntryDef' => sub {
    my $wire = wire_for('our $g; print $g // "u", "\n";', 'ourg');
    my @ops  = ops_of($wire, 'main::__PROGRAM__');
    ok scalar(grep { $_ eq 'EntryDef' } @ops), 'it is an EntryDef'
        or diag "ops: @ops";
    ok !scalar(grep { $_ eq 'StashAccess' } @ops), 'and not a StashAccess'
        or diag "ops: @ops";
};

subtest 'a never-written fully-qualified read is an EntryDef' => sub {
    my $wire = wire_for('print $main::nope // "u", "\n";', 'nope');
    my @ops  = ops_of($wire, 'main::__PROGRAM__');
    ok scalar(grep { $_ eq 'EntryDef' } @ops), 'it is an EntryDef'
        or diag "ops: @ops";
};

# The sigil survives the rename. `_` alone names three things ($_, @_, and the
# `-f _` filetest handle), so a sigil-less entry definition is not expressible
# and two names differing only by sigil are different variables.
subtest 'EntryDef keeps its sigil identity' => sub {
    require SoN::IR::NodeFactory;
    my $f = SoN::IR::NodeFactory->new;
    my $s = $f->make('EntryDef', stash_name => 'Foo', sigil => '$', var_name => 'bar');
    my $a = $f->make('EntryDef', stash_name => 'Foo', sigil => '@', var_name => 'bar');
    is $s->sigil, '$', 'scalar sigil readable';
    isnt $s->content_hash, $a->content_hash,
        '$Foo::bar and @Foo::bar remain different variables';

    my $missing = eval { $f->make('EntryDef', stash_name => 'Foo', var_name => 'bar'); 1 };
    ok !$missing, 'a sigil-less EntryDef is not constructible';
};

# @_ stays on its own node -- the split that made this rename honest.
subtest 'ArgsSource is untouched by the rename' => sub {
    my $wire = wire_for('sub f { my $n = shift; $n } print f(1), "\n";', 'args');
    my @ops  = ops_of($wire, 'main::f');
    ok scalar(grep { $_ eq 'ArgsSource' } @ops), '@_ is still an ArgsSource';
    ok !scalar(grep { $_ eq 'EntryDef' } @ops), 'and not an EntryDef';
};

done_testing;
