# ABOUTME: Constructs the walker cannot translate REFUSE by name, never crash.
# ABOUTME: An internal error masks the honest GAP and misdirects the reader.
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
    my $err = do { local $/; <$eh> } // '';
    return ($out, $err);
}

# AN INTERNAL ERROR IS THE WORST DIAGNOSTIC THIS PRODUCER EMITS. It is not a
# refusal -- the sub is silently SKIPPED, and the message points at StackSim or
# NodeFactory rather than at the construct, so the reader chases a simulator
# bug instead of an unlowered feature. The `split` case proved the pattern:
# what looked like a stack bug was a refusal nobody had written.
#
# WANTARRAY IS A RUNTIME FUNCTION OF THE CALLER'S CONTEXT, with THREE values,
# measured on 5.42.0:
#
#     my @l = w()   wantarray is true       list
#     my $s = w()   wantarray is false      scalar
#     w()           wantarray is UNDEF      void
#
# OpMap mapped it to `Constant` with no `value`, so the factory died
# "Required parameter 'value' is missing". No constant could have been right:
# a sub is translated ONCE and cannot see its caller, which is exactly why
# perl makes this a runtime function -- a fact this file already states twice
# in prose while the table said otherwise.
subtest 'wantarray refuses by name rather than crashing' => sub {
    my (undef, $err) = translate(
        'sub w { wantarray ? (1,2) : [] } my @l = w(); print scalar(@l);', 'wa');
    unlike $err, qr/INTERNAL ERROR/, 'no internal error';
    like $err, qr/GAP/, 'it refuses';
    like $err, qr/wantarray/, 'and the refusal names the construct';
};

# THE REFUSAL MUST NOT SPREAD. wantarray is the unlowered thing; a sub that
# does not use it must still translate.
subtest 'an ordinary sub is unaffected' => sub {
    my ($out, $err) = translate('sub f { return 7 } print f();', 'plainsub');
    unlike $err, qr/GAP|INTERNAL/, 'a plain sub still translates';
    like $out, qr/"op"\s*:\s*"Return"/, 'and reaches the wire';
};

# A BARE BLOCK WITH A `continue` compiles to a real enterloop whose nextop is
# the CONTINUE BODY, so the bare-block test (nextop == lastop) declined and it
# fell to the while-loop translator, which died "Stack underflow". perl's own
# t/cmd/switch.t contains it.
subtest 'a bare block with continue refuses by name' => sub {
    my (undef, $err) = translate(
        'sub f2 { $_ = shift(@_); { last if $_ == 1; } continue { return 20; } return $_; }'
        . ' print f2(0);', 'barecont');
    unlike $err, qr/INTERNAL ERROR/, 'no internal error';
    like $err, qr/GAP/, 'it refuses';
    like $err, qr/continue/, 'and the refusal names the construct';
};

# THE GUARD THAT MATTERS, and the one my first attempt failed. Keying the
# refusal on "nextop is not unstack" also caught `while + continue` and
# C-style `for`, both of which TRANSLATE CORRECTLY today -- measured at HEAD
# before the change, both emitted no GAP. The distinguishing property is the
# REDO target, which is what separates a block from a loop:
#
#     bare              next=leaveloop  redo=nextstate
#     bare + continue   next=pushmark   redo=ENTER
#     while             next=unstack    redo=nextstate
#     while + continue  next=stub       redo=padsv
#     C-style for       next=padsv      redo=stub
#
# Without these four cases the over-broad guard passed every other test in the
# suite.
subtest 'the loop forms that already worked still work' => sub {
    for my $case (
        ['my $i=0; while ($i<3) { $i++ } continue { } print $i;', 'while_cont'],
        ['for (my $i=0; $i<3; $i++) { } print "cfor";',           'cfor'],
        ['my $i=0; while ($i<3) { $i++ } print $i;',              'plain_while'],
        ['{ print "bare"; }',                                      'bare'],
    ) {
        my ($src, $name) = $case->@*;
        my (undef, $err) = translate($src, $name);
        unlike $err, qr/GAP|INTERNAL/, "$name still translates";
    }
};

# ONE-ARGUMENT `bless` defaults to the CURRENT PACKAGE, and perl supplies
# that at compile time -- `bless []` in main gives an object blessed into
# main. Measured:
#
#     bless [], "Foo"   ref is Foo    two args, works today
#     bless []          ref is main   ONE arg, died "Stack underflow"
#
# The one-arg form pops a class operand that was never pushed. Found in
# perl's own t/op/magic.t (`sub TIEARRAY {bless[]}`), which the file-level
# survey counted as translating.
# LOWERED, NOT REFUSED. The private field IS the argument count, so the fix is
# to pop the right number rather than to give up: the one-arg form blesses into
# the CURRENT PACKAGE, which perl resolves at compile time, so the missing
# operand is not unknown -- it simply is not on the stack.
subtest 'one-argument bless translates instead of underflowing' => sub {
    my ($out, $err) = translate('my $x = bless []; print ref($x);', 'bless1');
    unlike $err, qr/INTERNAL ERROR/, 'no internal error';
    unlike $err, qr/GAP/, 'and it does not need to refuse -- the arity is known';
    like $out, qr/"op"\s*:\s*"Call"/, 'the bless call reaches the wire';
};

# TWO-ARGUMENT bless already works and must keep working -- the refusal is for
# the defaulted class, not for bless.
subtest 'two-argument bless still translates' => sub {
    my (undef, $err) = translate('my $x = bless [], "Foo"; print ref($x);', 'bless2');
    unlike $err, qr/GAP|INTERNAL/, 'bless with an explicit class is unaffected';
};

# FOREACH OVER A MARK-CONSUMING BUILTIN. `foreach (unpack(...))` died "No mark
# on mark stack": the loop translator and unpack both want the mark, and the
# scout walk consumed it. The LIST-ASSIGNED form works, which is what says the
# defect is in the foreach pairing rather than in unpack:
#
#     my @u = unpack("W*","ab")        translates
#     foreach (unpack("W*","ab")) {}   INTERNAL ERROR
#
# From perl's own t/op/caller.t.
# LOWERED, NOT REFUSED -- and the refusal I first wrote here was treating a
# symptom. `foreach (unpack(...))` died "No mark on mark stack" because OpMap
# registered unpack as a 'mark' pop when it pushes none:
#
#     unpack("H2","A")   unpack vK/2   no pushmark, always two operands
#
# So the foreach and unpack were never contending for a mark; the table was
# wrong about unpack. Fixing the arity retired the GAP entirely. A refusal
# that exists because of a wrong table row is a TODO wearing a diagnostic.
subtest 'foreach over unpack translates' => sub {
    my ($out, $err) = translate(
        'my $o=""; foreach (unpack("W*","ab")) { $o .= $_ } print $o;', 'foreach_unpack');
    unlike $err, qr/INTERNAL ERROR/, 'no internal error';
    unlike $err, qr/GAP/, 'and no refusal -- the arity was the whole problem';
};

# BARE `select` takes ZERO arguments and returns the currently selected
# handle; the op says so (private=0 vs 1), while OpMap assumed a fixed 1-pop.
# perl's own t/op/select.t.
subtest 'bare select translates' => sub {
    my (undef, $err) = translate('my $x = select; print defined($x)?1:0;', 'select0');
    unlike $err, qr/INTERNAL ERROR|GAP/, 'zero-argument select is lowered';
};

subtest 'one-argument select still translates' => sub {
    my (undef, $err) = translate('my $x = select(STDOUT); print defined($x)?1:0;', 'select1');
    unlike $err, qr/INTERNAL ERROR|GAP/, 'the one-argument form is unaffected';
};

# THE LIST-ASSIGNED FORM STILL WORKS, so the refusal cannot be a blanket
# unpack refusal.
subtest 'list-assigned unpack still translates' => sub {
    my (undef, $err) = translate('my @u = unpack("W*","ab"); print scalar(@u);', 'unpack_list');
    unlike $err, qr/GAP|INTERNAL/, 'unpack in a list assignment is unaffected';
};

# A PACKAGE-VARIABLE ITERATOR IS NAMEABLE, and the list length has nothing to
# do with it. The glob is always LAST and always present:
#
#     for $f ("a")       const(a) | gv(f)
#     for $f ("a","b")   const(a) | const(b) | gv(f)
#
# The name was split off only when there were more than TWO bounds, so a
# one-element list refused as "unnameable iterator" -- and with two or more
# elements the refusal unwound with operands still on the stack, so a later pop
# underflowed. Nine of perl's re/*.t files are exactly this shape:
#
#     for $file ('./re/regexp.t', './t/re/regexp.t', ':re:regexp.t')
#
# EVERY LENGTH IS TESTED because the defect was keyed on length: a fix verified
# at one length says nothing about the others, which is how it survived.
subtest 'a package-variable iterator translates at every list length' => sub {
    for my $case (
        [q{for $f ('a') { print $f }},          'pkgiter1'],
        [q{for $f ('a','b') { print $f }},      'pkgiter2'],
        [q{for $f ('a','b','c') { print $f }},  'pkgiter3'],
    ) {
        my ($src, $name) = $case->@*;
        my (undef, $err) = translate($src, $name);
        unlike $err, qr/INTERNAL ERROR|GAP/, "$name translates";
    }
};

# THE OTHER ITERATOR FORMS must be unaffected -- a lexical iterator has a pad
# targ and never reaches this split, and the implicit $_ form is marked by
# OPpITER_DEF rather than carried on the stack.
subtest 'lexical and implicit iterators still translate' => sub {
    my (undef, $e1) = translate('for my $i (1,2,3) { print $i }', 'lexiter');
    unlike $e1, qr/INTERNAL ERROR|GAP/, 'a lexical iterator is unaffected';
    my (undef, $e2) = translate('for (1,2,3) { print $_ }', 'defiter');
    unlike $e2, qr/INTERNAL ERROR|GAP/, 'the implicit $_ iterator is unaffected';
};

done_testing;
