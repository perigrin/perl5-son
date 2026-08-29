# ABOUTME: A FieldAccess is stamped with the declared type of the field it reads.
# ABOUTME: The producer already records field types; this asserts the read reads them.
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
    print {$fh} "use 5.42.0;\nuse feature 'class';\nno warnings 'experimental::class';\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

sub nodes_of ($wire, $graph, $op) {
    my $g = $wire->{methods}{$graph} or return ();
    return grep { $_->{op} eq $op } ($g->{nodes} // [])->@*;
}

# THE DEFECT. `_wire_field_defaults` derives each field's type from its default
# and records it on the class section as `type`. A FieldAccess carries the
# field_index and field_stash that select exactly that record -- and nothing
# read it back, so every class-field read reached the wire `Unknown`. 21 of the
# 233 wire Unknowns measured over chalk's corpus were this one node kind.
subtest 'a field read takes the declared field type' => sub {
    my $wire = wire_for('class Counter { field $n = 0; method val { return $n } }
my $c = Counter->new; say($c->val);', 'intfield');
    is $wire->{classes}{Counter}{fields}[0]{type}, 'Int',
        'the field type is recorded on the class section';
    my ($fa) = nodes_of($wire, 'Counter::val', 'FieldAccess');
    ok defined $fa, 'the FieldAccess node exists' or return;
    is $fa->{stamp}, 'Int', 'the FieldAccess carries the field type';
};

# BILATERAL. A different declared type must produce a different stamp, or a
# hardcoded 'Int' would pass the subtest above.
subtest 'a string field reads as Str, not Int' => sub {
    my $wire = wire_for('class Tag { field $s = "hi"; method get { return $s } }
my $t = Tag->new; say($t->get);', 'strfield');
    is $wire->{classes}{Tag}{fields}[0]{type}, 'Str',
        'the field type is Str on the class section';
    my ($fa) = nodes_of($wire, 'Tag::get', 'FieldAccess');
    ok defined $fa, 'the FieldAccess node exists' or return;
    is $fa->{stamp}, 'Str', 'the FieldAccess carries Str';
};

# THE INDEX MUST SELECT. Two fields of different types in one class: reading
# the second must not pick up the first's type. A fix that ignored field_index
# would pass both subtests above and fail here.
subtest 'field_index selects the right field' => sub {
    my $wire = wire_for('class Box { field $n = 0; field $s = "x";
method second { return $s } }
my $b = Box->new; say($b->second);', 'twofields');
    my ($fa) = nodes_of($wire, 'Box::second', 'FieldAccess');
    ok defined $fa, 'the FieldAccess node exists' or return;
    is $fa->{field_index} // $fa->{fields}{field_index}, 1, 'it reads field 1';
    is $fa->{stamp}, 'Str', 'and carries field 1 type (Str), not field 0 (Int)';
};

# A field with NO default has no derived type, and must stay Unknown -- the fix
# propagates a recorded answer, it does not invent one.
subtest 'a field with no recorded type stays Unknown' => sub {
    my $wire = wire_for('class Bare { field $u; method get { return $u } }
my $b = Bare->new; say($b->get // 0);', 'nodefault');
    my ($fa) = nodes_of($wire, 'Bare::get', 'FieldAccess');
    ok defined $fa, 'the FieldAccess node exists' or return;
    is $fa->{stamp}, 'Unknown', 'an untyped field leaves the read Unknown';
};

# THE CONSEQUENCE. With the field read typed, the method that returns it has a
# determined return type -- and so does its callsite. This is the cascade the
# census predicted: one root fix resolves the chain above it.
subtest 'typing the field read types the method and its callsite' => sub {
    my $wire = wire_for('class Counter { field $n = 0; method val { return $n } }
my $c = Counter->new; my $v = $c->val; say($v);', 'cascade');
    is $wire->{classes}{Counter}{method_return_types}{val}, 'Int',
        'the method return type follows from the field read';
    my ($call) = grep { ($_->{fields}{name} // '') eq 'val' }
                 nodes_of($wire, 'main::__PROGRAM__', 'Call');
    ok defined $call, 'the method callsite exists' or return;
    is $call->{stamp}, 'Int', 'and the callsite carries it';
};

# A DEFAULT TYPES A FIELD ONLY WHEN NOTHING OUTSIDE CAN WRITE IT.
#
# `field $v :param = 0` recorded `type: Int` from the default. That is a true
# fact about the INITIALISER and a false one about the FIELD: `:param` lets a
# caller pass anything, and perl agrees --
#
#   Box->new(v => "hello")  ->  hello
#   Box->new(v => [1,2])    ->  an ARRAY ref
#
# So the declared type is the JOIN of the default with what `:param` admits.
# Nothing constrains the argument, so that is `Scalar`.
#
# The same shape as `my $x = 0; sub f() { $x }` -- Int at the assignment, but
# f's return is the join over every writer.
subtest 'a :param field widens to Scalar despite its default' => sub {
    my $wire = wire_for('class Box { field $v :param = 0;
method get { return $v } }
my $b = Box->new(v => 7); say($b->get);', 'param_widens');
    is $wire->{classes}{Box}{fields}[0]{type}, 'Scalar',
        'Int from the default joins with what :param admits';
};

# BILATERAL, and the case that makes the rule discriminating: with NO :param,
# nothing outside the class can write the field, so the default DOES type it.
subtest 'a non-param field keeps its default type' => sub {
    my $wire = wire_for('class Box { field $v = 0;
method get { return $v } }
my $b = Box->new; say($b->get);', 'nonparam_keeps');
    is $wire->{classes}{Box}{fields}[0]{type}, 'Int',
        'no :param means no outside writer, so Int stands';
};

# A Str default widens the same way -- the rule is about the WRITER, not the
# particular type, so a hardcoded Scalar-for-Int would not satisfy this.
subtest 'a :param Str field also widens' => sub {
    my $wire = wire_for('class Tag { field $s :param = "hi";
method get { return $s } }
my $t = Tag->new(s => "x"); say($t->get);', 'param_str_widens');
    is $wire->{classes}{Tag}{fields}[0]{type}, 'Scalar',
        'a Str default widens too';
};


# A :reader ACCESSOR RETURNS ITS FIELD'S TYPE, and nothing was wiring that up.
#
# The accessor body is synthesized as a PadAccess read of the field slot, NOT a
# FieldAccess -- so _stamp_field_reads does not see it. And backward inference
# correctly declines: `return $v` publishes no operator requirement, so there is
# nothing for a use site to say. The hole is real and its AUTHORITATIVE SOURCE
# is the field's declared type, which is a third connection.
#
# Found while unblocking chalk's vtable ABI probe: `class Box { field $v :param
# :reader = 0; ... }` put `Box::v` on the wire as Unknown while the field record
# beside it said type: Int.
subtest 'a :reader accessor returns its field type' => sub {
    # :param, so the field is Scalar -- an earlier version of this test asserted
    # Int here, which was the unsoundness itself (a caller may pass anything).
    my $wire = wire_for('class Box { field $v :param :reader = 0;
method half { $v / 2 } }
my $b = Box->new(v => 7); say($b->half);', 'reader_param');
    is $wire->{classes}{Box}{fields}[0]{type}, 'Scalar',
        'a :param field is Scalar, not its default type';
    my ($pad) = nodes_of($wire, 'Box::v', 'PadAccess');
    ok defined $pad, 'the accessor body reads the slot' or return;
    is $pad->{stamp}, 'Scalar', 'and the read carries the field type';
    is $wire->{classes}{Box}{method_return_types}{v}, 'Scalar',
        'so the accessor returns Scalar';
};

subtest 'a non-param reader returns the narrow default type' => sub {
    # No :param means no outside writer, so the default DOES type the field --
    # and the reader carries that. This is the case that shows the reader tracks
    # the field record rather than always widening.
    my $wire = wire_for('class Box { field $v :reader = 0; }
my $b = Box->new; say($b->v);', 'reader_narrow');
    is $wire->{classes}{Box}{fields}[0]{type}, 'Int',
        'a non-param defaulted field is Int';
    my ($pad) = nodes_of($wire, 'Box::v', 'PadAccess');
    ok defined $pad, 'the accessor body reads the slot' or return;
    is $pad->{stamp}, 'Int', 'and the reader carries Int';
    is $wire->{classes}{Box}{method_return_types}{v}, 'Int',
        'so the accessor returns Int';
};

# BILATERAL: a Str field's reader must be Str, or a hardcoded Int would pass.
subtest 'a Str field reader returns Str' => sub {
    my $wire = wire_for('class Tag { field $s :reader = "hi"; }
my $t = Tag->new; say($t->s);', 'reader_str');
    is $wire->{classes}{Tag}{fields}[0]{type}, 'Str',
        'the field records type Str';
    my ($pad) = nodes_of($wire, 'Tag::s', 'PadAccess');
    ok defined $pad, 'the accessor body reads the slot' or return;
    is $pad->{stamp}, 'Str', 'and the read carries Str, not Int';
};

# ONLY PROPAGATES -- and for a `:param` the floor is what it propagates. This
# subtest asserted `Unknown` while a `:param` with no default carried no type at
# all. It does now: `:param` admits any scalar, so the field is `Scalar` and the
# reader takes it (_floor_param_fields). The rule being pinned is unchanged --
# the reader claims exactly what the field record says, never more.
subtest 'a :param reader takes the field floor, and no more' => sub {
    my $wire = wire_for('class Bare { field $u :param :reader; }
my $b = Bare->new(u => 1); say($b->u // 0);', 'reader_untyped');
    my ($pad) = nodes_of($wire, 'Bare::u', 'PadAccess');
    ok defined $pad, 'the accessor body reads the slot' or return;
    is $wire->{classes}{Bare}{fields}[0]{type}, 'Scalar',
        'a :param with no default floors at Scalar';
    is $pad->{stamp}, $wire->{classes}{Bare}{fields}[0]{type},
        'and the reader claims exactly that, not a narrower guess';
};


done_testing;
