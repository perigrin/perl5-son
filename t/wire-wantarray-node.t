# ABOUTME: wantarray is a node the CALLSITE resolves, not a refusal.
# ABOUTME: The callsite already carries its context on the Call's `want` field.
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
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    my $w = (length $out && $out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    return ($w, $err);
}

sub nodes_of ($w, $meth) {
    return [ map { { $_->%*, ($_->{fields} // {})->%* } }
             ($w->{methods}{$meth}{nodes} // [])->@* ];
}

# WANTARRAY IS NOT A RUNTIME PROPERTY THE PRODUCER CANNOT SEE. It reports the
# CALLSITE's context, and the callsite already carries that: entersub's
# OPf_WANT reaches the wire as the Call node's `want` field, distinct per call.
#
#     my @l = f()   entersub lKS   want='list'
#     my $s = f()   entersub sKS   want='scalar'
#     f()           entersub vKS   want='void'
#
# The producer refused it on the grounds that "a perl sub is compiled once and
# cannot see its caller" -- true of perl's INTERPRETER, and not binding on a
# GRAPH. The same file already builds BOTH READINGS for a multi-value return
# and lets the callsite's `want` pick (_list_return_value). wantarray is that
# mechanism one node earlier.
#
# MEASURED on 5.42.0, all three contexts:
#
#     list    "1"     is_bool TRUE
#     scalar  ""      is_bool TRUE
#     void    undef
#
# so the type is join(Boolean, Undef) = Scalar. NOT Boolean alone: the void
# reading is genuinely undef, and claiming Boolean would lower an i1 for a
# value that is undef at runtime -- the trade this producer refuses.
subtest 'wantarray builds a node instead of refusing' => sub {
    my ($w, $err) = wire('sub f { wantarray } my @l = f(); print scalar(@l);', 'wa_node');
    unlike $err, qr/GAP/, 'wantarray no longer refuses';
    unlike $err, qr/INTERNAL/, 'and does not crash';
    ok $w, 'a graph was emitted' or return;
    my $n = nodes_of($w, 'main::f');
    ok scalar(grep { $_->{op} eq 'Wantarray' } $n->@*),
        'the callee body contains a Wantarray node';
};

# THE TYPE IS THE JOIN OVER ALL THREE CONTEXTS. Scalar, because void yields
# undef. A Boolean stamp here would be a claim perl does not support.
subtest 'wantarray is stamped Scalar, not Boolean' => sub {
    my ($w, $err) = wire('sub f { wantarray } my @l = f(); print scalar(@l);', 'wa_stamp');
    ok $w, 'a graph was emitted' or return;
    my ($wa) = grep { $_->{op} eq 'Wantarray' } nodes_of($w, 'main::f')->@*;
    ok defined $wa, 'the node exists' or return;
    isnt $wa->{stamp}, 'Boolean', 'not Boolean -- the void reading is undef';
    is $wa->{stamp}, 'Scalar', 'join(Boolean, Undef) is Scalar';
};

# THE CALLSITE STILL CARRIES ITS CONTEXT, which is what makes the node
# resolvable at all. Asserted so the node cannot be added while the edge that
# gives it meaning is dropped.
subtest 'each callsite records its own context' => sub {
    my ($w, $err) = wire(
        'sub f { wantarray } my @l = f(); my $s = f(); print scalar(@l), ($s//"u");', 'wa_calls');
    ok $w, 'a graph was emitted' or return;
    my @calls = grep { $_->{op} eq 'Call' && ($_->{name} // '') eq 'main::f' }
                nodes_of($w, 'main::__PROGRAM__')->@*;
    is scalar(@calls), 2, 'the two callsites are DISTINCT nodes, not hash-consed'
        or return;
    my %want = map { ($_->{want} // 'none') => 1 } @calls;
    ok $want{list},   'one callsite says list';
    ok $want{scalar}, 'the other says scalar';
};

# THE REAL IDIOM, and the one perl's own t/op/ uses: a ternary on wantarray
# returning a list or a scalar. Both arms must survive.
# THE REAL IDIOM, and the honest state of it. `wantarray ? (1,2) : "s"` now
# reaches a NAMED REFUSAL rather than a silent drop -- the wantarray half is
# lowered, and what remains unlowered is the multi-element list ARM, which is a
# separate construct with its own GAP (see the subtest below). Asserted as a
# refusal rather than as success, because claiming this translates today would
# be the over-claim this suite exists to prevent.
subtest 'the ternary idiom refuses on its list arm, not on wantarray' => sub {
    my (undef, $err) = wire(
        'sub f { wantarray ? (1,2) : "s" } my @l = f(); print scalar(@l);', 'wa_ternary');
    unlike $err, qr/INTERNAL/, 'no crash';
    like $err, qr/multi-element list arm/,
        'it refuses on the LIST ARM -- wantarray itself is lowered';
    unlike $err, qr/wantarray/, 'and the refusal is not about wantarray';
};

# A SINGLE-VALUE wantarray ternary is the part that fully works today.
subtest 'a single-value wantarray ternary translates end to end' => sub {
    my ($w, $err) = wire(
        'sub f { wantarray ? "L" : "S" } my @l = f(); print scalar(@l);', 'wa_single');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers';
    ok $w && $w->{methods}{'main::f'}, 'and the callee reaches the wire';
};

# A MULTI-ELEMENT TERNARY ARM IN A SUB BODY WAS A SILENT DROP, and the
# wantarray idiom is what surfaced it. The guard required the ternary op to be
# marked list-context -- but a sub's return context belongs to its CALLER, so
# the op carries no want at all:
#
#     my @l = $c ? (1,2) : ("s")     cond_expr lK/1   refused
#     sub g { $c ? (1,2) : ("s") }   cond_expr K/1    SILENTLY DROPPED the 1
#
# perl gives 2 elements both ways. Keyed on the ARM DELTA -- what the arm
# actually pushed -- rather than on the op's declared context.
subtest 'a multi-element ternary arm refuses in a sub body too' => sub {
    my (undef, $e1) = wire('my $c=1; my @l = $c ? (1,2) : ("s"); print scalar(@l);', 'mt_top');
    like $e1, qr/GAP/, 'the top-level form still refuses';
    my (undef, $e2) = wire('sub g { my $c=shift; $c ? (1,2) : ("s") } my @l=g(1); print scalar(@l);', 'mt_sub');
    like $e2, qr/GAP/, 'and the sub-body form no longer drops a value silently';
};

# A SINGLE-VALUE TERNARY IS UNAFFECTED -- the delta guard must not refuse the
# ordinary select this path exists to lower.
subtest 'a single-value ternary still translates' => sub {
    my (undef, $err) = wire('my $c=1; my $x = $c ? "y" : "n"; print $x;', 'single_ternary');
    unlike $err, qr/GAP|INTERNAL/, 'one value per arm still lowers';
};

done_testing;
