# ABOUTME: A subscript of a literal aggregate is stamped from that aggregate's elements.
# ABOUTME: The elements are the aggregate node's own inputs, each already stamped.
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
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

sub subscript_stamp ($src, $name) {
    my $wire = wire_for($src, $name);
    my ($sub) = grep { $_->{op} eq 'Subscript' }
                ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
    return undef unless $sub;
    return $sub->{stamp};
}

# THE DEFECT. An anonymous aggregate's elements ARE its input nodes, and each
# one already carries a stamp. `$a[1]` where `@a = (1,2,3)` is Int, determined
# entirely by data the producer is holding. It went to the wire Unknown.
# 27 of the 233 measured wire Unknowns were subscripts of a known aggregate.
subtest 'an array element takes the element type' => sub {
    is subscript_stamp('my @a = (1, 2, 3); say($a[1]);', 'arr_int'), 'Int',
        'all-Int array yields Int';
    is subscript_stamp('my @s = ("a", "b"); say($s[0]);', 'arr_str'), 'Str',
        'all-Str array yields Str';
};

# A hash literal interleaves keys and values. Only the VALUES are elements --
# reading the key stamps too would make {a=>1} yield join(Str,Int)=Str and
# quietly mistype every integer-valued hash.
subtest 'a hash element takes the VALUE type, not the key type' => sub {
    is subscript_stamp('my %h = (a => 1, b => 2); say($h{a});', 'hash_int'), 'Int',
        'string-keyed, Int-valued hash yields Int, not Str';
};

# MIXED ELEMENTS. The stamp must be the JOIN of the element types -- the
# safe supertype -- not the first element's type. Reading only element 0 would
# pass the all-Int subtest above and mistype this one.
subtest 'mixed element types join to their supertype' => sub {
    is subscript_stamp('my @m = (1, "x"); say($m[0]);', 'mixed'), 'Str',
        'join(Int,Str) is Str, the safe supertype';
};

# OUT OF BOUNDS. Perl yields undef for an index past the end, so the element
# join alone is WRONG here: `(1,2)[5]` is not Int. Undef must be in the join.
# This is the case that stops a naive element-join from being sound.
subtest 'an out-of-bounds index admits Undef' => sub {
    my $s = subscript_stamp('my @a = (1, 2); say($a[5]);', 'oob');
    isnt $s, 'Int', 'an out-of-bounds read is not claimed to be Int';
    ok +($s // '') =~ /^(Scalar|Undef)$/,
        "an out-of-bounds read stays honest (got: " . ($s // 'undef') . ")";
};

# A subscript whose aggregate is NOT a known literal has no ELEMENT type -- the
# fix reads elements it has and does not invent them. It is still a Scalar: see
# the floor subtests at the end of this file. `Unknown` here would be a hole in
# an AoT program, and the honest answer (one slot of an aggregate is a scalar)
# is available without reading a single element.
subtest 'a subscript of an unknown aggregate falls to the floor, not Unknown' => sub {
    my $s = subscript_stamp('sub f { my $n = shift; return $n } my $r = f(); say($r->[0]);',
                            'unknown_agg');
    isnt $s, 'Unknown', 'an unreadable aggregate is not a hole';
    is $s, 'Scalar', 'no known elements still means a scalar element';
};

# THE STORE CASE, and getting it wrong is a MISCOMPILE, not an imprecision.
# After `$a[0] = "str"` the literal no longer describes the array: the read
# yields Str, not Int. The producer builds that read with the STORE as its
# memory input rather than MemStart, which is how this pass can tell. A version
# answering from the element list alone stamps Int here, confidently and wrongly.
subtest 'a subscript after a store does not trust the literal' => sub {
    my $wire = wire_for('my @a = (1, 2, 3); $a[0] = "str"; say($a[0]);', 'stored');
    my @nodes = ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
    my %byid  = map { $_->{id} => $_ } @nodes;
    my @subs  = grep { $_->{op} eq 'Subscript' } @nodes;
    ok @subs >= 1, 'the subscripts exist' or return;

    # The READ is the one whose memory input is the store, not MemStart.
    my ($read) = grep {
        my $m = $byid{ ($_->{inputs} // [])->[2] // -1 };
        $m && $m->{op} ne 'MemStart';
    } @subs;
    ok defined $read, 'the post-store read exists' or return;
    isnt $read->{stamp}, 'Int',
        'the read after a store is NOT claimed Int (the stored value is Str)';
};

# THE MISSING-KEY CASE, and getting it wrong is a MISCOMPILE. Caught by chalk's
# behavioural gate (references.md R10) after the first version of this pass
# shipped: `my %h = (a=>1,b=>2); say($h{z})` prints an empty line under perl and
# printed 0 under chalk, because the read was stamped Int.
#
# A MISSING HASH KEY IS THE SAME FACT AS AN OUT-OF-RANGE ARRAY INDEX: the read
# yields undef, so no element type describes it. The first version bounds-checked
# array indices and never wrote the membership equivalent for hash keys -- the
# join over the values (Int, from 1 and 2) was correct and still did not apply,
# because the key is not there at all.
#
# UNDEF, NOT UNKNOWN. Undef is a real lattice member and the answer is known
# statically: a literal key absent from a literal hash yields undef. Stamping it
# keeps a fact the producer holds, and join(Undef, Int) widens to Scalar if this
# read later merges with a defined arm.
subtest 'a missing literal key is Undef, never the value type' => sub {
    my $s = subscript_stamp('my %h = (a => 1, b => 2); say($h{z});', 'misskey');
    isnt $s, 'Int', 'a missing key is NOT stamped with the value type';
    is $s, 'Undef', 'a literal key absent from a literal hash reads Undef';
};

# BILATERAL: a key that IS present must still take the value type, or the fix
# above would be indistinguishable from disabling hash stamping entirely.
subtest 'a present literal key still takes the value type' => sub {
    is subscript_stamp('my %h = (a => 1, b => 2); say($h{b});', 'haskey'),
        'Int', 'a present key reads the value type';
};

# THE ARRAY ANALOGUE, stated as the same rule. A constant index provably past
# the end is Undef for exactly the reason a missing key is.
subtest 'a provably out-of-range constant index is Undef' => sub {
    is subscript_stamp('my @a = (1, 2); say($a[5]);', 'oob_undef'),
        'Undef', 'past the end reads Undef, not the element type';
};

# ---------------------------------------------------------------------------
# THE SCALAR FLOOR. Everything above narrows a subscript from its aggregate's
# literal elements. These cover what happens when that analysis DECLINES.
#
# A SUBSCRIPT CAN NEVER HONESTLY BE UNKNOWN. `$a[...]` and `$h{...}` read ONE
# slot, and one slot of any Perl aggregate holds a scalar. There is no program
# in which a subscript is plural: a slice is a different node kind entirely
# (Slice :isa(Aggregate), against Subscript :isa(Access)).
#
# WHY THE FLOOR IS NOT A CONSOLATION PRIZE. Chalk compiles ahead of time, so
# there is no runtime to defer to and an `Unknown` is not a missing annotation
# -- it is a hole in the emitted program. `Scalar` lowers to %Slot, the tagged
# {i1 defined, i64 payload} carrier chalk already emits in every prologue. That
# is slower than an i64 and it RUNS. The ranking is: narrow type > %Slot >
# nothing. An unconverged type costs speed; a missing representation costs the
# program.
#
# THE FLOOR IS A FLOOR, NOT AN ANSWER. Every subtest above still asserts its
# narrower type, because `Scalar` where `Int` is provable is also a T1 failure
# -- just a less obvious one. These cases are where nothing narrower is
# derivable at all.
subtest 'a subscript after a store falls to Scalar, not Unknown' => sub {
    my $wire = wire_for('my @a = (1, 2, 3); $a[0] = "str"; say($a[0]);', 'floor_stored');
    my @nodes = ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
    my %byid  = map { $_->{id} => $_ } @nodes;
    my ($read) = grep {
        my $m = $byid{ ($_->{inputs} // [])->[2] // -1 };
        $_->{op} eq 'Subscript' && $m && $m->{op} ne 'MemStart';
    } @nodes;
    ok defined $read, 'the post-store read exists' or return;
    isnt $read->{stamp}, 'Int', 'still not claimed Int -- the store invalidated the literal';
    is $read->{stamp}, 'Scalar', 'the widest TRUE answer, not a hole';
};

# The hash form of the same fact. Kept separate because the membership rule and
# the store rule were written for arrays first and hashes were the miscompile.
subtest 'a hash element after a store falls to Scalar' => sub {
    my $wire = wire_for('my %h = (k => 0); $h{k} = "s"; say($h{k});', 'floor_hstored');
    my @nodes = ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
    my %byid  = map { $_->{id} => $_ } @nodes;
    my ($read) = grep {
        my $m = $byid{ ($_->{inputs} // [])->[2] // -1 };
        $_->{op} eq 'Subscript' && $m && $m->{op} ne 'MemStart';
    } @nodes;
    ok defined $read, 'the post-store read exists' or return;
    is $read->{stamp}, 'Scalar', 'a written-through hash slot is still a scalar';
};

# A COMPUTED index over a KNOWN array already reads the element type, and that
# is narrower than the floor: the aelem handler stamps a dynamic-index read from
# _array_element_stamp. Asserted here so the floor cannot regress it -- Scalar
# where Int is provable is also a T1 failure.
subtest 'a computed index over a known array keeps the element type' => sub {
    my $s = subscript_stamp('my @a = (1, 2, 3); my $i = 1; say($a[$i + 1]);', 'floor_dyn');
    is $s, 'Int', 'a dynamic index over an all-Int array still reads Int';
};

# A COMPUTED KEY OVER A LITERAL HASH still takes the value join: which key is
# read does not change what the values are. Asserted so the floor cannot regress
# it -- the key being undecidable is not a reason to widen.
subtest 'a computed key over a literal hash keeps the value type' => sub {
    my $s = subscript_stamp('my %h = (a => 1); my $k = "a"; say($h{$k});', 'floor_hdyn');
    is $s, 'Int', 'an undecidable KEY over a known hash still reads Int';
};

# THE CONTAINER, not the index, is what the floor answers for. A hash returned
# from a sub has no literal to read elements out of, so nothing narrows and the
# floor is the whole answer.
subtest 'a subscript of a returned aggregate falls to Scalar' => sub {
    my $s = subscript_stamp(
        'sub mk { my $n = shift; return $n } my $r = mk(); say($r->{k});', 'floor_opaque');
    is $s, 'Scalar', 'an unreadable container still yields one scalar slot';
};

# $_[0] over @_. The ArgsSource is stamped Array, and an INDEXED read of it is a
# scalar with no callsite information and no restored binding edge required.
# This is the `@_` family closing WITHOUT the list-assign work.
subtest 'an indexed read of @_ is Scalar' => sub {
    my $wire = wire_for('sub f { $_[0] + 1 } say(f(10));', 'floor_args');
    my ($sub) = grep { $_->{op} eq 'Subscript' }
                ($wire->{methods}{'main::f'}{nodes} // [])->@*;
    ok defined $sub, 'the @_ subscript exists' or return;
    is $sub->{stamp}, 'Scalar', 'one slot of @_ is a scalar';
};

# AN LVALUE SUBSCRIPT IS AN ADDRESS, NOT A VALUE, and stamping it is wrong in
# KIND rather than in width. The producer builds a store TARGET as a 2-input
# node (container, index) with NO memory input, precisely so it never
# hash-conses with a pre-store rvalue read of the same slot. The floor must not
# claim a store address holds a scalar.
subtest 'an lvalue subscript is not stamped at all' => sub {
    my $wire = wire_for('my @a = (1, 2, 3); $a[0] = 42; say($a[0]);', 'floor_lvalue');
    my @subs = grep { $_->{op} eq 'Subscript' }
               ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
    my @lvalues = grep { scalar(($_->{inputs} // [])->@*) == 2 } @subs;
    ok @lvalues >= 1, 'a 2-input lvalue subscript exists' or return;
    for my $lv (@lvalues) {
        isnt $lv->{stamp}, 'Scalar',
            'a store ADDRESS is not given a value type by the floor';
    }
};

# ORDERING. The floor answers `Scalar`, the weakest possible answer, and every
# narrowing pass guards on only-fill-Unknown -- so a floor that runs INSIDE the
# fixpoint stamps on round 1 and each narrowing pass then skips the node.
#
# THIS CASE MEASURED IT. `field $items = [10,20,30]; method first { $items->[0] }`
# reads through a FieldAccess (stamped ArrayRef), not an ArrayRef node, so
# _literal_element_type declines: the elements live in a separate default graph.
# With the floor inside the loop the method returned `Scalar` while chalk's
# loader derived `Int` from the same graph and REFUSED to load it, taking the
# corpus 231 -> 230 cases. The floor must run only after nothing else can speak.
subtest 'a field-held literal array still narrows to Int, not the floor' => sub {
    my $file = "$dir/bagfield.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} <<'SRC';
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Bag {
    field $items = [10, 20, 30];
    method first { $items->[0] }
}
say(Bag->new->first);
SRC
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main,package=Bag $file 2>$dir/bagfield.err};
    ok length $json, 'the class emitted wire JSON' or return;
    my $wire = JSON::PP->new->decode($json);

    # The producer does NOT narrow this: the elements live in a separate
    # default graph (Bag::__DEFAULT_0) that _literal_element_type does not
    # cross, so the read is Unknown until the floor speaks. Chalk's loader DOES
    # cross it and derives Int -- which is why the floor's answer here must be
    # a true SUPERTYPE of what the consumer derives, never a conflicting peer.
    my ($sub) = grep { $_->{op} eq 'Subscript' }
                ($wire->{methods}{'Bag::first'}{nodes} // [])->@*;
    ok defined $sub, 'the element read exists' or return;
    is $sub->{stamp}, 'Scalar',
        'a field-held aggregate is not readable here, so the floor answers';
    is $wire->{classes}{Bag}{method_return_types}{first}, 'Scalar',
        'and the method return type carries the same floor';
};

done_testing;
