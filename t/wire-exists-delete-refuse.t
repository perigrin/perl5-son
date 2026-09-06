# ABOUTME: exists and delete REFUSE rather than lowering to a wrong answer.
# ABOUTME: exists was mapped to Defined over the KEY, which is always true.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub translate ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> };
    return ($out, $err // '');
}

# A SILENT WRONG ANSWER, and it was reachable from ordinary code. OpMap mapped
#
#     exists  => [1, 'Defined', 1, 0]
#
# so `exists $h{zz}` became Defined(Constant("zz")) -- asking whether the
# STRING "zz" is defined, which it always is. perl prints "no"; the graph meant
# "yes". Membership and definedness are DIFFERENT QUESTIONS, measured:
#
#     my %h = (a => undef);
#     exists $h{a}    true      the key is there
#     defined $h{a}   false     its value is not
#
# and the operand was wrong on top of that: the Defined took the KEY, never the
# slot, so no version of this mapping could have been right.
# EXISTS IS NOW LOWERED, not refused -- see t/wire-exists-node.t for the node's
# contract. What this file still pins is the thing that made the refusal
# necessary: no Defined node may be emitted over the key. That assertion is
# meaningful on both sides of the change, which is why it is kept rather than
# deleted with the refusal.
subtest 'exists never emits a Defined over the key' => sub {
    my ($out, $err) = translate('my %h=(a=>1); print exists $h{zz} ? "y" : "n";', 'ex');
    unlike $err, qr/INTERNAL/, 'no crash';
    unlike $out, qr/"op"\s*:\s*"Defined"/,
        'no Defined node is emitted over the key -- that was the miscompile';
    like $out, qr/"op"\s*:\s*"Exists"/, 'an Exists node is emitted instead';
};

# DELETE MUTATES AND YIELDS. It removes the key AND returns the value:
#
#     my %h=(a=>1,b=>2); my $d = delete $h{a};   $d is 1, and a is gone
#
# It reached the wire as Call(delete, Constant("a")) :Unknown -- the KEY as its
# only operand (the OpMap gave it a pop_count of 1, exactly the defect `exists`
# had above), no hash, and no memory edge, so a later read could not observe the
# removal. It is now a Delete node carrying [container, key, memory], which is
# the same shape Exists carries plus the memory ADVANCE a mutation needs.
subtest 'delete carries its container and threads the removal' => sub {
    my ($out, $err) = translate('my %h=(a=>1,b=>2); my $d = delete $h{a}; print $d;', 'del');
    unlike $err, qr/GAP/, 'delete is no longer refused';
    like $out, qr/"op"\s*:\s*"Delete"/, 'a Delete node is emitted';
    unlike $out, qr/"name"\s*:\s*"delete"/,
        'and not the operand-less Call that dropped the mutation';
};

# A SLICE IS STILL REFUSED, and the discriminator is a PRIVATE bit rather than
# an OPf flag -- measured, `delete $h{a}` is private=0x0 and
# `delete @h{qw(a b)}` is private=0x40 (OPpSLICE). Keyed on OPf_STACKED the
# refusal never fired and the slice popped one key off a list of them, emitting
# Delete(Constant, HashLiteral) with container and key SWAPPED.
subtest 'a delete slice still refuses, and names itself' => sub {
    my (undef, $derr) = translate('my %h=(a=>1,b=>2); delete @h{qw(a b)};', 'delslice');
    like $derr, qr/GAP/, 'the slice is refused, loudly';
    like $derr, qr/delete/, 'the GAP says "delete"';
    like $derr, qr/slice/, '... and says which form';
};

# `exists &sub` NO LONGER REFUSES. It asks about a symbol-table CV slot rather
# than container membership, which is an EntryDef with sigil '&' -- so the
# question is "does this entry exist", exactly what Exists means, with the
# container and key collapsed into one addressed entry.
subtest 'exists &sub lowers, and delete is unaffected' => sub {
    my ($out, $serr) = translate('sub f {} print exists &f ? 1 : 0;', 'exsub');
    unlike $serr, qr/GAP|INTERNAL/, '`exists &sub` lowers';
    like $out, qr/"sigil"\s*:\s*"&"/,
        '... to a symbol-table entry with the code sigil';
};

# NEIGHBOURING HASH OPERATIONS STILL WORK. The refusal must be for these two
# ops, not for hash access generally.
subtest 'ordinary hash reads and writes are untouched' => sub {
    my ($out, $err) = translate('my %h=(a=>1); $h{b}=2; print $h{a};', 'hashok');
    unlike $err, qr/GAP/, 'a plain hash read/write does not refuse';
    like $out, qr/"op"\s*:\s*"Subscript"/, 'and still builds its Subscript';
};

done_testing;
