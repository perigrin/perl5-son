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

done_testing;
