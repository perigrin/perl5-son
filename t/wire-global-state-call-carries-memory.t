# ABOUTME: A call that ADVANCES the memory chain must also CARRY a memory input.
# ABOUTME: Producing a memory version without naming one makes the node invisible to readers.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f;
    my $d = eval { JSON::PP->new->decode($j) } or return undef;
    return $d->{methods}{'main::__PROGRAM__'};
}

# THE INVARIANT: a node that produces a new memory version names the old one.
# Every other memory point satisfies it -- EntryWrite is [slot, value, memory],
# an aggregate builtin is [args..., memory] -- and that is what lets a reader
# recognise the chain structurally instead of by name.
#
# `require` AND `dofile` BROKE IT. FromOptree advances memory for them
# (%GLOBAL_STATE_BUILTIN, "the import MUST NOT float above the require") but
# builds the node with only its argument:
#
#     690 Call in=[689]  name=require     <- produces memory, names none
#
# So a consumer walking the chain cannot tell it is a memory point. Measured
# on comp/require.t, that made `Phi(1190) in=[Call(require), EntryWrite]` --
# a merge of two memory chains -- look like a VALUE Phi, which bound the
# EntryWrite and then asked to render a store as an expression.
subtest 'require carries the memory it advances' => sub {
    my $g = graph_of('require POSIX; print "ok\n";');
    ok $g, 'it translates' or return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my ($req) = grep { ($_->{op} // '') eq 'Call'
                    && (($_->{fields} // {})->{name} // '') eq 'require' }
                $g->{nodes}->@*;
    ok $req, 'there is a require Call' or return;

    my @in = ($req->{inputs} // [])->@*;
    is scalar(@in), 2, 'it has a memory input beside its argument'
        or diag "inputs: @in";
    return unless @in >= 2;

    my $mem = $by{ $in[-1] };
    like +($mem->{op} // ''), qr/\A(?:MemStart|EntryWrite|Assign|Call|Phi|CellWrite|Delete)\z/,
        '... and that input is a memory point';
};

# TWO REQUIRES CHAIN, which is the ordering the memory edge exists to express:
# the second must name the first.
subtest 'two requires chain through memory' => sub {
    my $g = graph_of('require POSIX; require Carp; print "ok\n";');
    ok $g, 'it translates' or return;

    my @req = sort { $a->{id} <=> $b->{id} }
              grep { ($_->{op} // '') eq 'Call'
                  && (($_->{fields} // {})->{name} // '') eq 'require' }
              $g->{nodes}->@*;
    is scalar(@req), 2, 'two require Calls' or return;

    my @in = ($req[1]{inputs} // [])->@*;
    is $in[-1], $req[0]{id},
        'the second names the first as its memory';
};

# THE SAME VIOLATION, FOUND BY AUDITING THE PRODUCER rather than by a corpus
# file pointing at it. `RegexSubst` calls set_memory -- a destructive s///
# stores into its target, and a later read must observe it -- while taking
# only [target, pattern?, replacement?]. Measured on
# `our $g = "aaa"; $g =~ s/a/b/; $g =~ s/b/c/`:
#
#     11 RegexSubst in=[3]    no memory input
#     12 RegexSubst in=[11]   chained through its TARGET, not through memory
#
# The ordering happened to fall out of the data edge here, which is exactly
# how a missing memory edge stays invisible until something else needs it.
# TODO UNTIL RegexSubst CAN SAY WHERE ITS MEMORY IS. Its inputs are
# [target, pattern?, replacement?] -- TWO optional slots -- so appending memory
# makes position ambiguous: a 2-input node could be [target, pattern],
# [target, replacement] or [target, memory]. It already carries
# `pattern_is_input` for exactly this reason, and fixing this properly means a
# second flag or always-present slots, which is a wire change of its own.
#
# Pinned rather than fixed so the finding stays visible: the audit that found
# it is the producer-side sweep recommended in
# docs/plans/2026-09-14-a-memory-point-must-carry-memory.md, and it found this
# without any corpus file pointing at it.
subtest 'a destructive s/// carries the memory it advances' => sub {
    todo 'RegexSubst has two optional input slots and cannot place memory' => sub {
    my $g = graph_of('our $g = "aaa"; $g =~ s/a/b/; print "$g\n";');
    ok $g, 'it translates' or return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my ($sub) = grep { ($_->{op} // '') eq 'RegexSubst' } $g->{nodes}->@*;
    ok $sub, 'there is a RegexSubst' or return;

    my @in = ($sub->{inputs} // [])->@*;
    my $mem = $by{ $in[-1] // -1 };
    like +($mem->{op} // ''),
        qr/\A(?:MemStart|EntryWrite|Assign|Call|Phi|CellWrite|Delete|RegexSubst)\z/,
        'its last input is a memory point';
    };
};

done_testing;
