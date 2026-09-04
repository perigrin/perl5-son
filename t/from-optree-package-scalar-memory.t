# ABOUTME: A package scalar is observable across a call, so it needs memory, not just SSA.
# ABOUTME: Rebinding a scope key cannot express a write one sub makes and another sub reads.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub graphs_of ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    return $data->{methods};
}

# THE SSA SCOPE MAP IS NOT ENOUGH FOR A PACKAGE SCALAR. A pad slot is private
# to its sub, so rebinding a key is the whole semantics. A package scalar is
# reachable from every sub in the program, so a write in one and a read in
# another are ordered only if they share a memory chain.
#
# Measured before this fix, on
#
#     our $g = "a";
#     sub peek { return $g }
#     sub poke { $g = "changed" }
#     print peek(); poke(); print peek();
#
#   perl : a then changed
#   graph: main::poke was Start, Constant, Return -- NO STORE AT ALL, and
#          main::peek returned a bare EntryDef with no memory input, so the
#          two peek() calls were identical nodes that hash-cons to one value.
#
# The aggregate side already had this right: `push @a, 1` is a Call over
# [EntryDef, value, MemStart] and the push IS the store. A scalar assignment
# has no builtin op to carry it, so it needs a store node of its own --
# EntryWrite, modelled on CellWrite, which solved this exact problem for
# closure captures.
subtest 'a package scalar write emits a store' => sub {
    my $m = graphs_of(qq{our \$g = "a";\nsub poke { \$g = "changed" }\npoke();\nprint qq{\$g\\n};\n});
    ok defined $m, 'translates' or return;
    my $poke = $m->{'main::poke'};
    ok defined $poke, 'the writing sub is in the output' or return;

    my @ops = map { $_->{op} } $poke->{nodes}->@*;
    ok scalar(grep { $_ eq 'EntryWrite' } @ops),
        'the assignment emits an EntryWrite, not nothing'
        or diag "poke ops: @ops";
};

subtest 'a package scalar read takes a memory input' => sub {
    my $m = graphs_of(qq{our \$g = "a";\nsub peek { return \$g }\nprint peek(), qq{\\n};\n});
    ok defined $m, 'translates' or return;
    my $peek = $m->{'main::peek'};
    ok defined $peek, 'the reading sub is in the output' or return;

    my ($ed) = grep { $_->{op} eq 'EntryDef' } $peek->{nodes}->@*;
    ok defined $ed, 'the read is an EntryDef' or return;
    ok scalar($ed->{inputs}->@*),
        'it has a memory input, so a later write is observable'
        or diag "EntryDef inputs: " . JSON::PP->new->encode($ed->{inputs} // []);
};

# The pad case must not acquire memory it does not need: a lexical is private
# to its sub and SSA rebinding IS its semantics.
subtest 'a lexical scalar stays pure SSA' => sub {
    my $m = graphs_of(qq{sub f { my \$l = 1; \$l = \$l + 1; return \$l }\nprint f(), qq{\\n};\n});
    ok defined $m, 'translates' or return;
    my @ops = map { $_->{op} } $m->{'main::f'}{nodes}->@*;
    ok !scalar(grep { $_ eq 'EntryWrite' } @ops),
        'no EntryWrite for a pad slot' or diag "f ops: @ops";
};

done_testing;
