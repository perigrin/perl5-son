# ABOUTME: A read-modify-write of a package scalar must store its result, in every spelling.
# ABOUTME: And a call must advance memory, so a later read observes what the callee wrote.

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

# ONE OPERATOR, FIVE DECLARATION SITES. `$n++` is one spelling of
# read-modify-write on a package scalar; perl compiles the family into FOUR
# different optree shapes, and only two of them reached a store. Measured on
#
#     our $n = 0; sub f { SPELLING; 1 } f(); f(); print "n=$n\n";
#
#   $n++ / $n-- / ++$n   preinc/predec over a gvsv   Add computed, NO store
#   $n += 3 / $n *= 2    STACKED add/multiply        NOTHING AT ALL emitted
#   $n .= "x"            STACKED multiconcat         correct (EntryWrite)
#   $n = $n + 1          sassign                     correct (EntryWrite)
#
# The first two families are silent miscompiles: perl prints 2 and 6, the
# graph holds a floating Add consumed by nobody, or no arithmetic whatsoever.
subtest 'every read-modify-write spelling stores back' => sub {
    my %spelling = (
        'post-increment'  => '$n++',
        'post-decrement'  => '$n--',
        'pre-increment'   => '++$n',
        'pre-decrement'   => '--$n',
        'add-assign'      => '$n += 3',
        'subtract-assign' => '$n -= 3',
        'multiply-assign' => '$n *= 2',
        'modulo-assign'   => '$n %= 7',
        'concat-assign'   => '$n .= "x"',
        'plain-reassign'  => '$n = $n + 1',
    );

    for my $name (sort keys %spelling) {
        my $m = graphs_of(
            qq{our \$n = 4;\nsub f { $spelling{$name}; 1 }\nf();\nprint qq{\$n\\n};\n});
        ok defined $m, "$name: translates" or next;
        my $f = $m->{'main::f'};
        ok defined $f, "$name: the mutating sub is in the output" or next;

        my @ops = map { $_->{op} } $f->{nodes}->@*;
        ok scalar(grep { $_ eq 'EntryWrite' } @ops),
            "$name ($spelling{$name}): the mutation emits an EntryWrite"
            or diag "f ops: @ops";
    }
};

# A CALL IS A MEMORY BARRIER WHEN A PACKAGE SCALAR EXISTS TO BE WRITTEN. The
# producer already rebinds `our $n = 0` in the SSA scope map AND emits the
# EntryWrite; without the barrier the rebind wins forever, so the read in
#
#     our $n = 0; sub bump { $n++; 1 } bump(); bump(); print "n=$n\n";
#
# resolved to the literal Constant 0 the initial store carried. Measured:
# Print's operand chain reached `Constant integer 0` and no EntryDef at all,
# so the program printed 0 where perl prints 2.
subtest 'a read after a call goes through memory, not the initial value' => sub {
    my $m = graphs_of(
        qq{our \$n = 0;\nsub bump { \$n++; 1 }\nbump();\nbump();\nprint qq{n=\$n\\n};\n});
    ok defined $m, 'translates' or return;
    my $prog = $m->{'main::__PROGRAM__'};
    ok defined $prog, 'the program body is in the output' or return;

    my %by_id = map { $_->{id} => $_ } $prog->{nodes}->@*;
    my ($print) = grep { $_->{op} eq 'Print' } $prog->{nodes}->@*;
    ok defined $print, 'the print is in the graph' or return;

    # Walk the Print's data cone and look for the package read.
    my (@queue, %seen, @cone) = ($print->{inputs}->@*);
    while (@queue) {
        my $id = shift @queue;
        next if $seen{$id}++;
        my $n = $by_id{$id} or next;
        push @cone, $n;
        push @queue, ($n->{inputs} // [])->@*;
    }

    my ($read) = grep {
        $_->{op} eq 'EntryDef' && ($_->{fields}{symbol} // '') eq 'n'
    } @cone;
    ok defined $read,
        'the interpolated $n is a package read, not a forwarded constant'
        or diag 'print cone ops: ' . join ', ',
            map { $_->{op} . ($_->{fields}{value} // '') } @cone;

    ok scalar(($read->{inputs} // [])->@*),
        'and that read carries a memory input'
        or diag 'EntryDef inputs: ' . JSON::PP->new->encode($read->{inputs} // []);

    # The memory it reads must be downstream of the calls, or it cannot
    # observe them.
    my @calls = grep { $_->{op} eq 'Call' } $prog->{nodes}->@*;
    ok scalar(@calls) >= 2, 'both bump() calls are in the graph' or return;
    my %mem_cone;
    @queue = ($read->{inputs}->@*);
    %seen = ();
    while (@queue) {
        my $id = shift @queue;
        next if $seen{$id}++;
        my $n = $by_id{$id} or next;
        $mem_cone{$n->{op}}++;
        push @queue, ($n->{inputs} // [])->@*;
    }
    ok $mem_cone{Call},
        'the read memory is downstream of a Call, so the callee write is visible'
        or diag 'memory cone: ' . join ', ', sort keys %mem_cone;
};

# A LEXICAL MUST NOT ACQUIRE THE BARRIER. A pad slot is private to its sub, so
# no call can write it and ordering its reads against every call would lose
# real optimisations for nothing.
subtest 'a lexical read-modify-write stays pure SSA' => sub {
    my $m = graphs_of(
        qq{sub f { my \$l = 1; \$l++; \$l += 2; return \$l }\nprint f(), qq{\\n};\n});
    ok defined $m, 'translates' or return;
    my @ops = map { $_->{op} } $m->{'main::f'}{nodes}->@*;
    ok !scalar(grep { $_ eq 'EntryWrite' } @ops),
        'no EntryWrite for a pad slot' or diag "f ops: @ops";
};

# A MEMORY-ROUTED READ MUST KEEP THE TYPE OF THE VALUE IT READS. Routing a
# package-scalar read through memory must not cost it its stamp: the binding
# says what the variable holds, and that stays true when the read is spelled
# as a memory edge rather than as the value.
#
# ASSERTED END TO END, not on the stamp field. A direct assertion that the
# read is stamped passes even with the stamp dropped -- EntryDef's class
# default is narrow enough at the sites that are easy to reach. What actually
# breaks is the loop-carried fixpoint, so that is what this pins. Measured on
# `$x = 0; while ($x < 3) { $x = $x + 1 }` (perl's t/base/while.t) with the
# read unstamped, the back-edge came out
#
#     Add(EntryDef:Unknown, Constant:Int)  ->  Unknown
#
# against an Int induction Phi, so _patch_loop_phi GAPped with
# "loop-carried value loses its stamp" and the file went CLEAN -> refused.
#
# THE UNIT SUITE DOES NOT COVER THIS. It stayed fully green through the
# regression; only running perl's own t/base caught it.
subtest 'a package scalar drives a while loop' => sub {
    my $m = graphs_of(
        qq{\$x = 0;\nwhile (\$x < 3) { \$x = \$x + 1; }\nprint qq{\$x\\n};\n});
    ok defined $m, 'it translates rather than GAPping on the loop-carried stamp'
        or return;
    ok defined $m->{'main::__PROGRAM__'}, 'the program body survives';
};

done_testing;
