# ABOUTME: A `:param` field with no default is Scalar -- the same answer the
# ABOUTME: with-a-default case already computes, from strictly less evidence.
use v5.42.0;
use Test2::V0;
use JSON::PP;

my $SCRATCH = '/tmp/claude-1001/-home-perigrin-dev-perl5-son/03347934-6f4e-47de-b925-06eaae0f6389/scratchpad';

sub wire ($src) {
    my $file = "$SCRATCH/t-param-$$.pl";
    open my $fh, '>', $file or die $!;
    print {$fh} $src;
    close $fh;
    my $json = qx{perl -Ilib -Iblib/lib -MO=SoN,json,package=main -- '$file' 2>/dev/null};
    unlink $file;
    return decode_json($json);
}

sub field_type ($d, $class, $fname) {
    my $fields = $d->{classes}{$class}{fields} or return undef;
    for my $f (@$fields) { return $f->{type} if ($f->{name} // '') eq $fname }
    return undef;
}

my $PAIR = <<'SRC';
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Pair {
    field $left  :param :reader;
    field $right :param :reader;
}
my $p = Pair->new(left => 10, right => 20);
say($p->left + $p->right);
SRC

# THE GAP, and the answer is already written down one branch away. For a
# `:param` field WITH a default, _extract_fields records
# join(default, Scalar) = Scalar, and its comment states why: `:param` lets a
# caller pass anything, so the default types the INITIALISER, not the FIELD.
#
#   Box->new(v => "hello")   ->  hello
#   Box->new(v => [1,2])     ->  an ARRAY ref
#
# A `:param` field with NO default admits EXACTLY THE SAME SET. It is the same
# `Scalar`, reached with strictly less information -- there is simply no
# default to join with. The producer recorded no type at all instead, which is
# the audit's bucket two: the evidence was in hand and the question unasked.
#
# `Scalar` IS NOT NOTHING. It excludes Array, Hash, Code and Glob, and it is
# refinable -- a method body narrows it (`$v / 2` meets Scalar with Num).
subtest 'a :param field with no default is Scalar' => sub {
    my $d = wire($PAIR);
    is(field_type($d, 'Pair', '$left'),  'Scalar', '$left is Scalar');
    is(field_type($d, 'Pair', '$right'), 'Scalar', '$right is Scalar');
};

# AND THE READER REACHES THE WIRE TYPED. _stamp_reader_accessors already knows
# how to stamp a :reader body from its field's type and already records the
# method return type from the same source; it declined only because the field
# record had no type to offer. So this is the connection being restored, not a
# new analysis.
subtest 'the :reader accessor and its return type follow' => sub {
    my $d = wire($PAIR);
    my $g = $d->{methods}{'Pair::left'} or return fail('Pair::left graph exists');
    my ($pad) = grep { $_->{op} eq 'PadAccess' } $g->{nodes}->@*;
    ok($pad, 'the accessor body reads a pad slot') or return;
    is($pad->{stamp}, 'Scalar', 'the reader body is typed');
    is($d->{classes}{Pair}{method_return_types}{left}, 'Scalar',
        'and the method return type records it');
};

# THE NEGATIVE. A field that is NOT a :param has no outside writer, so its
# default stands and must NOT be widened to Scalar. Without this subtest,
# stamping every field Scalar would satisfy everything above.
subtest 'a non-:param field keeps its narrow default type' => sub {
    my $d = wire(<<'SRC');
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :reader = 0;
}
say(Counter->new->n);
SRC
    is(field_type($d, 'Counter', '$n'), 'Int',
        'a field with no :param keeps Int from its default');
};

# AND THE BILATERAL CASE: :param WITH a default already answers Scalar. It is
# asserted here so the two paths are pinned to ONE answer -- if a later change
# makes them disagree, this fails even though each is defensible alone.
subtest 'a :param field with a default is also Scalar' => sub {
    my $d = wire(<<'SRC');
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Box {
    field $v :param :reader = 0;
}
say(Box->new(v => 5)->v);
SRC
    is(field_type($d, 'Box', '$v'), 'Scalar',
        'a :param with a default was already Scalar; both paths agree');
};

done_testing;
