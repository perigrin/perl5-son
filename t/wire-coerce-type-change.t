# ABOUTME: A Coerce belongs where the value's TYPE changes -- meet(from,to) != from.
# ABOUTME: `my $h = "hello"; $h + 1` needs one; `Int` in a Str position does not.
use v5.42.0;
use Test2::V0;
use JSON::PP ();
use File::Temp ();

sub wire ($src) {
    my ($fh, $tmp) = File::Temp::tempfile(SUFFIX => '.pl', UNLINK => 1);
    print {$fh} $src;
    close $fh;
    my $json = qx{$^X -Ilib -Iblib/lib -MO=SoN,json,package=main -- $tmp 2>/dev/null};
    return JSON::PP::decode_json($json);
}

sub nodes_of ($d, $g) { return ( $d->{methods}{$g}{nodes} // [] )->@* }

sub coerces_in ($d, $g) {
    return map { [ $_->{fields}{from_repr}, $_->{fields}{to_repr} ] }
           grep { $_->{op} eq 'Coerce' } nodes_of($d, $g);
}

sub node_op ($d, $g, $op) {
    my ($n) = grep { $_->{op} eq $op } nodes_of($d, $g);
    return $n;
}

# THE RULE. A Coerce belongs where the value's TYPE changes -- that is,
# where the source does NOT already satisfy the target:
#
#     meet(from, to) != from   =>  Coerce[from -> to]
#
# The meet is only the PREDICATE; the target is always the requirement. And
# because it compares the result against ONE side, the rule is DIRECTED even
# though meet is symmetric:
#
#     meet(Str, Num) = Num != Str   ->  coerce
#     meet(Num, Str) = Num == Num   ->  do not
#
# One direction of each pair fires, so the coercion relation is acyclic.
#
# NOT `meet == None`. That is the narrower case of two INCOMPARABLE types, and
# it misses every narrowing: `Str -> Num` and `Scalar -> Str` both need a
# conversion and neither meets to None. Measured over chalk's corpus, the
# ==None rule found ZERO sites and this one finds 28.
subtest 'a Str used as a number is coerced' => sub {
    my $d = wire(qq{use 5.42.0;\nno warnings;\nsub f { my \$h = "hello"; return \$h + 1 }\nsay(f());\n});
    my @c = coerces_in($d, 'main::f');
    my ($str_to_num) = grep { $_->[0] eq 'Str' && $_->[1] eq 'Num' } @c;
    ok($str_to_num, 'the Str operand of + carries a Coerce[Str -> Num]')
        or diag('coerces present: ' . join(', ', map { "$_->[0]->$_->[1]" } @c));
};

# AND THE STAMP FOLLOWS. Without the coercion the Add takes join(Str, Int) =
# Str, which is a WRONG answer, not merely an imprecise one: perl returns 1,
# an integer. With the operand converted the join is over Num and Int.
subtest 'the Add yields a number, not a string' => sub {
    my $d = wire(qq{use 5.42.0;\nno warnings;\nsub f { my \$h = "hello"; return \$h + 1 }\nsay(f());\n});
    my $add = node_op($d, 'main::f', 'Add');
    ok($add, 'the Add exists') or return;
    isnt($add->{stamp}, 'Str', 'Add over a string operand is NOT stamped Str');
    is($add->{stamp}, 'Num', 'it is a Num -- perl returns 1, a number');
};

# THE NEGATIVE, and it is what keeps the rule honest. An Int in a Str position
# needs NO coercion on the type axis: meet(Int, Str) = Int, so the source
# already satisfies the target. Any rule that fires here is converting a
# REPRESENTATION, which is not this pass's business.
subtest 'an Int used as a string needs no type coercion' => sub {
    my $d = wire(qq{use 5.42.0;\nsub g { my \$n = 41; return \$n + 1 }\nsay(g());\n});
    my @c = coerces_in($d, 'main::g');
    my ($int_to_num) = grep { $_->[0] eq 'Int' && $_->[1] eq 'Num' } @c;
    ok(!$int_to_num, 'no Coerce[Int -> Num] is inserted -- Int already satisfies Num')
        or diag('coerces present: ' . join(', ', map { "$_->[0]->$_->[1]" } @c));
};

# DIRECTED, NOT SYMMETRIC. The mirror of the firing case must not fire, or the
# coercion relation is cyclic and the pass can oscillate.
subtest 'the mirror direction does not fire' => sub {
    my $d = wire(qq{use 5.42.0;\nsub h { my \$n = 41; return \$n . "x" }\nsay(h());\n});
    my @c = coerces_in($d, 'main::h');
    my ($num_to_str) = grep { $_->[0] eq 'Num' && $_->[1] eq 'Str' } @c;
    ok(!$num_to_str, 'a number in a string position gets no TYPE coercion');
};

# A COERCED OPERAND IS NOT A LEAF. The Add's re-derivation changes the sub's
# return type, which changes every callsite -- and the passes that own those
# answers fill only `Unknown`, so they will not correct a stamp that is merely
# WRONG. Without the invalidation the wire contradicts itself: Return yields
# Num while return_type and the Call both still say Str.
subtest 'the corrected type reaches the return record and the callsite' => sub {
    my $d = wire(qq{use 5.42.0;\nno warnings;\nsub f { my \$h = "hello"; return \$h + 1 }\nsay(f());\n});
    is($d->{classes}{main}{subs}{f}{return_type}, 'Num',
        'the sub return_type follows the corrected Add');
    my $call = node_op($d, 'main::__PROGRAM__', 'Call');
    ok($call, 'the callsite exists') or return;
    is($call->{stamp}, 'Num', 'and the callsite carries it');
};

done_testing;
