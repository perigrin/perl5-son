# ABOUTME: Compares B::SoN's STAMPS against types observed in a real perl run.
# ABOUTME: 98 test files assert stamps; none checked one against perl until this.
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;

# THE BLIND SPOT THIS CLOSES. Every other test in this suite asserts graph
# SHAPE -- which nodes exist, what their inputs are. A WRONG STAMP on a
# well-shaped graph passes all of them. That is the same gap pvm found on the
# checker side: a coverage number says how OFTEN a type was assigned and
# nothing about whether it was RIGHT, and the two move independently.
#
# perl is the oracle. observe_types.pl (pvm's, taken with permission and
# unmodified) maps a LIVE value to a lattice type using the paper's membership
# tests rather than SV flags -- flags record a value's HISTORY, so "hi" reads
# as PVNV once anything has numified it.
#
# THE LIMIT IS HONEST AND WORTH STATING: this covers only executed paths, and
# only the values the corpus observes. A known limit, unlike a hand-written
# table's unknown one.
#
# FOUR OUTCOMES, counted separately because they are not the same failure:
#
#   exact   the stamp is the observed type
#   wider   correct but less precise (Scalar where Int was observed) -- fine,
#           and the direction a sound checker is allowed to be wrong in
#   WRONG   the stamp excludes the observed value -- the only failing case,
#           because a consumer ACTS on it
#   none    no stamp, or Unknown -- silence, which is not a wrong answer

my $CORPUS = 't/oracle/mutation_corpus.pl';
plan skip_all => "corpus not present" unless -r $CORPUS;

# --- 1. what perl actually produced ---------------------------------------
my $observed_json = qx{$^X $CORPUS 2>/dev/null};
my $observed = eval { JSON::PP->new->decode($observed_json) };
ok $observed && @$observed, 'the corpus ran and reported observations'
    or do { done_testing; exit };

# --- 2. is each observed type COMPATIBLE with the lattice? -----------------
# The producer stamps IR nodes, not source variables, so a name-by-name join
# is not available without a per-statement map. What IS checkable, and is the
# assertion that would have caught this session's defects, is that perl's
# answer for each construct matches the type the producer claims for it.
#
# Kept as an explicit table so a disagreement names the construct rather than
# a node id. Each entry was measured, and the ones marked with why are the
# cases that were WRONG in emitted IR at some point this session.
my %EXPECTED = (
    # a whole-aggregate read AFTER a mutation. `shift @a; scalar(@a)` gave 3
    # where perl gives 2 -- Count had no memory input, so the read could not
    # observe the mutation however well the write was threaded.
    count_after_shift        => 'Int',
    count_after_push         => 'Int',
    count_after_splice       => 'Int',

    # the mutators' own results. push/unshift yield the NEW LENGTH; splice
    # yields the REMOVED ELEMENTS, which is why it is deliberately unstamped
    # rather than claimed Int.
    push_returns             => 'Int',
    unshift_returns          => 'Int',
    splice_returns_element   => 'Int',
    shift_returns_element    => 'Int',

    # the aliasing write-back: a foreach iterator is an ALIAS, so a body write
    # mutates the source.
    element_after_alias_write => 'Int',
    scalar_after_alias_subst  => 'Str',

    # scalar context. perl folds the `scalar` op away in a sub's TRAILING
    # position, so anything keyed on that op saw nothing and the sub returned
    # the ARRAY.
    trailing_scalar_read     => 'Int',
    array_in_scalar_assign   => 'Int',
    hash_in_scalar_assign    => 'Int',
    last_index               => 'Int',

    # builtins whose result type perl defines. printf and formline return a
    # real boolean -- but they CAN FAIL, which is why the producer stamps them
    # Scalar (join(Boolean, Undef)) rather than Boolean.
    printf_returns           => 'Bool',
    caller_scalar            => 'Str',
    prototype_missing        => 'Undef',
    formline_returns         => 'Bool',
);

# --- 2a. THE STAMP-VS-OBSERVED COMPARISON ---------------------------------
# The real check: for each construct, what does the PRODUCER claim, and does
# it admit the value perl actually produced?
#
# One construct per program, printed last, so the node feeding the Print IS
# the value under test -- that avoids needing a per-variable node map the wire
# does not carry.
my %LATTICE_PARENT = (
    Int => 'Num', Num => 'Str', Str => 'Scalar', Boolean => 'Scalar',
    Bool => 'Scalar', Undef => 'Scalar', Scalar => 'List',
    Array => 'List', Hash => 'List',
);
sub admits ($stamp, $observed) {
    return 1 if $stamp eq $observed;
    # Bool and Boolean are the two spellings of one type across the wire.
    return 1 if ($stamp eq 'Boolean' && $observed eq 'Bool')
             || ($stamp eq 'Bool' && $observed eq 'Boolean');
    # WIDER IS ALLOWED: a stamp above the observed type in the lattice is
    # correct but less precise, which is the direction a sound answer may err.
    my $t = $observed;
    my %guard;
    while (defined $t && !$guard{$t}++) {
        return 1 if $t eq $stamp;
        $t = $LATTICE_PARENT{$t};
    }
    return 0;
}

my %CONSTRUCT = (
    count_after_shift => 'my @a=(1,2,3); shift @a; print scalar(@a);',
    count_after_push  => 'my @a=(1,2,3); push @a,4; print scalar(@a);',
    push_returns      => 'my @a=(1,2); my $r = push(@a,3,4); print $r;',
    trailing_scalar_read =>
        'sub f { my @a=(1,2,3); scalar @a } print f();',
    array_in_scalar_assign => 'my @a=(1,2,3); my $n = @a; print $n;',
    last_index        => 'my @a=(1,2,3); print $#a;',
    caller_scalar     => 'sub w { my $c = caller; $c } print w();',
);

subtest 'the producer stamp admits the value perl produced' => sub {
    my %obs = map { $_->{name} => $_->{type} } @$observed;
    require File::Temp;
    my $dir = File::Temp::tempdir(CLEANUP => 1);

    for my $name (sort keys %CONSTRUCT) {
        my $want = $obs{$name};
        ok defined $want, "$name was observed" or next;

        my $file = "$dir/$name.pl";
        open my $fh, '>', $file or die;
        print {$fh} "use 5.42.0;\nno warnings;\n$CONSTRUCT{$name}\n";
        close $fh;

        my $out = qx{$^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null};
        my $w = ($out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
        ok $w, "$name lowers" or next;

        my @nodes = map { $_->{nodes}->@* } values $w->{methods}->%*;
        my %by = map { $_->{id} => $_ } @nodes;
        my ($print) = grep { $_->{op} eq 'Print' } @nodes;
        ok $print, "$name builds a Print" or next;

        # Step past a Coerce: it is a representation change, not the value.
        my $node = $by{ ($print->{inputs} // [])->[0] // '' };
        $node = $by{ ($node->{inputs} // [])->[0] // '' }
            if $node && $node->{op} eq 'Coerce';
        my $stamp = ($node // {})->{stamp};

        if (!defined $stamp || $stamp eq 'Unknown') {
            # SILENCE IS NOT A WRONG ANSWER. Recorded, not failed.
            note "$name: no stamp (observed $want) -- silence, not a wrong type";
            pass "$name is not WRONG";
            next;
        }
        ok admits($stamp, $want),
            "$name: stamp $stamp admits observed $want";
    }
};

my %seen;
for my $o (@$observed) {
    my ($name, $type) = ($o->{name}, $o->{type});
    $seen{$name} = 1;
    my $want = $EXPECTED{$name};
    if (!defined $want) {
        fail "observation '$name' has no expected entry -- add it or remove it";
        next;
    }
    is $type, $want, "perl observes $name as $want";
}

# A CORPUS ENTRY THAT NEVER RUNS IS NOT COVERAGE. An expected type for an
# observation the corpus never emits looks like a checked case and is not --
# the allow-list hazard, one layer over.
my @missing = grep { !$seen{$_} } sort keys %EXPECTED;
is scalar(@missing), 0, 'every expected observation was actually produced'
    or diag("never observed: @missing");

done_testing;
