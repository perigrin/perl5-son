# ABOUTME: A loop whose CONDITION reads memory ($a[$i] while ...) translates, never underflows/crashes (zhi 019f35f1).
# ABOUTME: It read at the loop-header memory version; it was refused until loops carried one for every store.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN;
use SoN::FromOptree;

# `$i=$i+1 while $a[$i]` and `while($a[$i]){...}` -- the loop CONDITION reads an
# array element. It was refused while a condition read had no loop-header memory
# Phi to go through; the loop builds one whenever its body moves memory now
# (t/deparse-a-loop-carries-its-stores.t), and a body that moves none reads the
# same version every pass. What this file guarded stands: never underflow the
# stack sim (fused multideref path) and never build a Subscript with undef memory
# (unfused aelem path, "consumers on an undefined value").

sub translate_err ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $cerr = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $cerr" if $cerr;
    my $err = dies { SoN::FromOptree->translate($cv) };
    return $err // '';
}

subtest 'statement-modifier while with a memory-reading condition translates' => sub {
    my $err = translate_err('sub { my @a=(1,2,3); my $i=0; $i=$i+1 while $a[$i]; $i }');
    is($err, '', 'it translates') or diag($err);
    unlike($err, qr/underflow/i, 'not a stack underflow');
    unlike($err, qr/consumers on an undefined/,
        'not the undef-memory crash');
};

subtest 'block while with a memory-reading condition translates' => sub {
    my $err = translate_err('sub { my @a=(0,1,2); my $i=0; while($a[$i]){$i=$i+1} $i }');
    is($err, '', 'it translates') or diag($err);
    unlike($err, qr/underflow/i, 'not a stack underflow');
    unlike($err, qr/consumers on an undefined/,
        'not the undef-memory crash');
};

subtest 'a hash-element loop condition translates' => sub {
    my $err = translate_err('sub { my %h=(a=>1); my $k="a"; while($h{$k}){$k=""} $k }');
    is($err, '', 'it translates') or diag($err);
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
