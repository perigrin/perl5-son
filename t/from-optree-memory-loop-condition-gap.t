# ABOUTME: A loop whose CONDITION reads memory ($a[$i] while ...) GAPs loudly, never underflows/crashes (zhi 019f35f1).
# ABOUTME: Memory-reading loop conditions are not yet lowered; the producer must refuse with a specific GAP, not a silent swallow.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# `$i=$i+1 while $a[$i]` and `while($a[$i]){...}` -- the loop CONDITION reads an
# array element. Memory-reading loop conditions are not yet lowered (memory-SSA
# through a loop-header memory-Phi for a condition read is unimplemented), so the
# producer must GAP LOUDLY with a specific message -- never underflow the stack
# sim (fused multideref path) and never build a Subscript with undef memory
# (unfused aelem path, "consumers on an undefined value"). A silent swallow drops
# the whole sub from the JSON with no diagnostic; B::SoN only re-emits GAP:-prefixed
# refusals, so the message MUST carry the GAP: prefix to surface.

sub translate_err ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $cerr = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $cerr" if $cerr;
    my $err = dies { SoN::FromOptree->translate($cv) };
    return $err // '';
}

subtest 'statement-modifier while with a memory-reading condition GAPs' => sub {
    my $err = translate_err('sub { my @a=(1,2,3); my $i=0; $i=$i+1 while $a[$i]; $i }');
    like($err, qr/^GAP: memory-reading loop condition/,
        'memory-reading modifier-while condition produces a specific GAP') or diag($err);
    unlike($err, qr/underflow/i, 'not a stack underflow');
    unlike($err, qr/consumers on an undefined/,
        'not the undef-memory crash');
};

subtest 'block while with a memory-reading condition GAPs' => sub {
    my $err = translate_err('sub { my @a=(0,1,2); my $i=0; while($a[$i]){$i=$i+1} $i }');
    like($err, qr/^GAP: memory-reading loop condition/,
        'memory-reading block-while condition produces a specific GAP') or diag($err);
    unlike($err, qr/underflow/i, 'not a stack underflow');
    unlike($err, qr/consumers on an undefined/,
        'not the undef-memory crash');
};

subtest 'a hash-element loop condition GAPs' => sub {
    my $err = translate_err('sub { my %h=(a=>1); my $k="a"; while($h{$k}){$k=""} $k }');
    like($err, qr/^GAP: memory-reading loop condition/,
        'memory-reading helem condition produces a specific GAP') or diag($err);
    unlike($err, qr/consumers on an undefined/, 'not the undef-memory crash');
};

# Regressions: real loops whose CONDITION does not read memory still translate,
# including a loop whose BODY reads/writes memory (body memory access is 2b-4,
# supported -- only the CONDITION read is the GAP).

subtest 'a scalar-condition statement-modifier while still translates' => sub {
    my $err = translate_err('sub { my $i=0; $i=$i+1 while $i<3; $i }');
    is($err, '', 'a real statement-modifier while loop is not misread as a GAP');
};

subtest 'a scalar-condition block while still translates' => sub {
    my $err = translate_err('sub { my $i=0; while($i<3){$i=$i+1} $i }');
    is($err, '', 'a real block while loop still translates');
};

subtest 'a block while with a body memory store still translates' => sub {
    my $err = translate_err('sub { my @a=(1,2,3); my $i=0; while($i<3){$a[$i]=$i; $i=$i+1} $a[0] }');
    is($err, '', 'a body element store (scalar condition) still translates');
};

subtest 'a headless while(1) with a body memory READ is not misblamed on the condition' => sub {
    # while(1) has a constant condition with no and/or terminator; the scan must
    # stop at the loop-body boundary (unstack/leaveloop), NOT walk into the body
    # and misattribute a BODY memory read to the CONDITION. The body read here is
    # its own honest GAP (last/loop-control or body shape), but the message must
    # NOT falsely claim the condition reads memory.
    my $err = translate_err('sub { my @a=(1,2); my $i=0; while(1){$i=$i+$a[0]; last if $i>5} $i }');
    unlike($err, qr/memory-reading loop condition/,
        'a while(1) body read is not misblamed as a memory-reading CONDITION') or diag($err);
};

done_testing();
