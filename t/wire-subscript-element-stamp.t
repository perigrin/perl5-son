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
    ok +($s // '') =~ /^(Unknown|Scalar|Undef)$/,
        "an out-of-bounds read stays honest (got: " . ($s // 'undef') . ")";
};

# A subscript whose aggregate is NOT a known literal must stay Unknown. The fix
# reads elements it has; it does not invent them.
subtest 'a subscript of an unknown aggregate stays Unknown' => sub {
    is subscript_stamp('sub f { my $n = shift; return $n } my $r = f(); say($r->[0]);',
                       'unknown_agg'),
        'Unknown', 'no known elements means no claim';
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

done_testing;
