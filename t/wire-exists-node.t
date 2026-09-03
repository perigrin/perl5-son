# ABOUTME: exists asks whether a key is PRESENT -- its own node, not Defined.
# ABOUTME: Container from the op's nulled first child, key from the stack.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    my $w = (length $out && $out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    my @n = $w ? (map { { $_->%*, ($_->{fields} // {})->%* } }
                  ($w->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*) : ();
    return (\@n, $err);
}

# MEMBERSHIP IS NOT DEFINEDNESS, and OpMap mapped `exists` onto the Defined
# node -- over the KEY, not the slot -- so `exists $h{zz}` became
# Defined(Constant("zz")), always true. perl prints "" for a missing key; the
# graph meant 1. A SILENT WRONG ANSWER from ordinary code.
#
#     my %h = (a => 1, u => undef);
#     exists $h{u}    TRUE     the key is present
#     defined $h{u}   false    its value is not
#     exists $h{zz}   false
#
# WHERE THE OPERANDS ARE, measured under suppress_peep -- which is how B::SoN
# always runs, and which stops the multideref fusion from ever forming:
#
#     exists $h{a}   exists UNOP private=1    first: null -> padhv
#     exists $a[0]   exists UNOP private=1    first: null -> padav
#     exists &f      exists UNOP private=65   first: null -> null
#
# The CONTAINER is one null below ->first; the KEY is on the stack. No aux
# decoding is involved: the fused multideref only exists WITHOUT suppression,
# which is not the configuration the walker sees.
subtest 'exists builds its own node' => sub {
    my ($n, $err) = wire('my %h=(a=>1); print exists $h{a} ? 1 : 0;', 'ex_node');
    unlike $err, qr/GAP/, 'exists no longer refuses';
    unlike $err, qr/INTERNAL/, 'and does not crash';
    ok scalar(grep { $_->{op} eq 'Exists' } $n->@*), 'an Exists node is built';
    is scalar(grep { $_->{op} eq 'Defined' } $n->@*), 0,
        'and NOT a Defined node -- that was the miscompile';
};

# THE CONTAINER MUST REACH THE NODE. The old mapping took the KEY ALONE, so it
# could not answer the question whatever it was called. This is the subtest
# that distinguishes a real fix from a rename.
subtest 'the container and the key are both operands' => sub {
    my ($n, $err) = wire('my %h=(a=>1); print exists $h{a} ? 1 : 0;', 'ex_operands');
    my %byid = map { $_->{id} => $_ } $n->@*;
    my ($e) = grep { $_->{op} eq 'Exists' } $n->@*;
    ok defined $e, 'the node exists' or return;
    my @in = map { $byid{$_} } ($e->{inputs} // [])->@*;
    cmp_ok scalar(@in), '>=', 2, 'it has at least two operands' or return;
    ok +($in[0] && $in[0]{op} =~ /HashLiteral|PadAccess|ArrayLiteral/),
        "operand 0 is the container (got $in[0]{op})";
    ok +($in[1] && $in[1]{op} eq 'Constant' && ($in[1]{value} // '') eq 'a'),
        'operand 1 is the key';
};

# THE RESULT IS Boolean: is_bool(exists $h{a}) is true, and unlike print or
# open there is no failure path yielding undef -- exists always answers.
subtest 'exists yields a Boolean' => sub {
    my ($n, undef) = wire('my %h=(a=>1); print exists $h{a} ? 1 : 0;', 'ex_stamp');
    my ($e) = grep { $_->{op} eq 'Exists' } $n->@*;
    ok defined $e, 'the node exists' or return;
    is $e->{stamp}, 'Boolean', 'is_bool(exists ...) is true, so Boolean';
};

subtest 'exists works on an array element' => sub {
    my ($n, $err) = wire('my @a=(1,2); print exists $a[0] ? 1 : 0;', 'ex_array');
    unlike $err, qr/GAP|INTERNAL/, 'an array exists translates';
    ok scalar(grep { $_->{op} eq 'Exists' } $n->@*), 'and builds an Exists node';
};

# `exists &sub` IS A DIFFERENT QUESTION -- is this CV present in the symbol
# table -- and it is the ONLY form carrying OPpEXISTS_SUB (private 65 = 64|1).
# It is NOT lowered as container membership: the operand is an EntryDef with
# sigil '&', so container and key collapse into one addressed entry.
#
# NOT FOLDED TO A CONSTANT, though the answer is readable at compile time. The
# symbol table is mutable at runtime -- measured, `exists &late` is 0, then
# `*late = sub {1}` makes it 1 -- so the answer must be read when asked.
subtest 'exists &sub reads the symbol table' => sub {
    my ($n, $err) = wire('sub f {} print exists &f ? 1 : 0;', 'ex_sub');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    my ($entry) = grep { $_->{op} eq 'EntryDef' } $n->@*;
    ok $entry, 'a symbol-table entry is built' or return;
    is +($entry->{fields}{sigil} // ''), '&', '... with the code sigil';

    my ($ex) = grep { $_->{op} eq 'Exists' } $n->@*;
    ok $ex, 'and an Exists tests it';
    ok scalar(grep { $_ == $entry->{id} } ($ex->{inputs} // [])->@*),
        '... over that entry';
};

# A PLAIN READ MUST NOT BECOME AN Exists. The discriminator is the private
# flag; keyed on the op NAME alone, every element read would become a
# membership test.
subtest 'a plain element read is still a Subscript' => sub {
    my ($n, $err) = wire('my %h=(a=>1); print $h{a};', 'ex_plain');
    is scalar(grep { $_->{op} eq 'Exists' } $n->@*), 0,
        'no Exists node for an ordinary read';
    ok scalar(grep { $_->{op} eq 'Subscript' } $n->@*), 'it is still a Subscript';
};

done_testing;
