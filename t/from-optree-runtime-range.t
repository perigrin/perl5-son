# ABOUTME: A list-context runtime range (1..$n) expands to N elements; the
# ABOUTME: scalar-context flip-flop is a different, stateful operator.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub run_perl ($src) {
    my $f = "$dir/r." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $f 2>&1);
    unlink $f;
    return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
    unlink $f;
    return ( eval { JSON::PP->new->decode($j) }, $e );
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my ( $data, $err ) = graph_of($src);
    unless ( $data && $data->{methods}{'main::__PROGRAM__'} ) {
        fail "$name: translates";
        diag $err;
        return;
    }
    my $d   = SoN::Deparse->new;
    my $out = eval { $d->render($data) };
    unless ( defined $out ) {
        my $g = $d->gap // $@ // '(no reason)';
        $g =~ s/\n.*//s;
        fail "$name: renders";
        diag $g;
        return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# THREE OP NAMES, TWO CONSTRUCTS. `range`, `flip` and `flop` are emitted for
# both spellings and the CONTEXT FLAG separates them -- measured, with the
# constants read from B rather than recalled (OPf_WANT_LIST=3,
# OPf_WANT_SCALAR=2, mask 3):
#
#     my @q = (1..$n)                 7 <|> range(other->8)[$:2,3] lK/1
#     print "x" if ($l==2)..($l==4)   8 <|> range(other->9)[$:4,5] sK/1
#
# LIST context is a counted expansion: N elements, no state. SCALAR context is
# the flip-flop operator, which carries state across evaluations and is a
# different thing wearing the same op name -- the same shape as `goto` being
# polymorphic over its operand.
#
# A constant range (1..4) constant-folds to a const[AV] and never reaches the
# walker at all, so only a non-constant bound produces these ops.
#
# The refusal covered BOTH and its message named only the list one. Refusing a
# construct is honest; refusing two under one message is not, because the
# message cannot be matched to a cause.

# ATTEMPTED AND REVERTED 2026-09-26. The split by context is correct and the
# list form is still not lowered, because `range` IS A BRANCH OP REACHED BEFORE
# ITS OPERANDS. Measured exec order for `my @q = (1..$n)`:
#
#     6  <0> pushmark s
#     7  <|> range(other->8)[$:2,3] lK/1
#     8      <0> padsv[$n:1,3] s          <- the HIGH bound, on ->next
#     9      <1> flop lK
#     e  <$> const[IV 1] s                <- the LOW bound, on ->other
#     f  <1> flip[$:2,3] lK/LINENUM
#
# So at the moment `range` is reached the stack holds NEITHER bound: one
# arrives down ->next and the other down ->other, and `flip`/`flop` close over
# them. Popping two operands at the `range` op gave "fewer than two bounds on
# the stack" -- a Range node cannot simply be built there.
#
# A correct lowering has to walk both arms the way the branch handlers do and
# join them, which is the shape _translate_foreach_range already has for the
# loop case. Not built; the honest refusal stands rather than a guess.
#
# The SCALAR form additionally hits a DIFFERENT refusal first ("range inside a
# loop body"), so the flip-flop subtest below cannot be reached from a `for`
# loop at all until that one moves.
subtest 'a list-context runtime range expands' => sub {
    my $todo = todo 'a runtime range is a branch op; both bounds arrive on separate arms';
    round_trips( <<'SRC', 'a range with a variable upper bound' );
my $n = 4;
my @q = (1 .. $n);
print scalar(@q), " @q\n";
SRC

    round_trips( <<'SRC', 'both bounds runtime' );
my $lo = 2;
my $hi = 5;
my @q = ($lo .. $hi);
print scalar(@q), " @q\n";
SRC

    round_trips( <<'SRC', 'an empty range yields no elements' );
my $n = 0;
my @q = (1 .. $n);
print scalar(@q), "\n";
SRC
};

# THE SCALAR FORM STAYS REFUSED, and its message must say which construct it
# is. Per [[a-refusal-test-must-name-its-cause]] a shared message cannot be
# matched to a cause, so this pins the SPLIT rather than merely that something
# refuses.
subtest 'the scalar-context flip-flop refuses under its own name' => sub {
    my $todo = todo 'the refusal does not yet name which construct it is';
    my ( undef, $err ) = graph_of( <<'SRC' );
my @out;
for my $l (1 .. 6) { push @out, $l if ($l == 2) .. ($l == 4) }
print "@out\n";
SRC
    like $err, qr/flip-flop/,
        'the refusal names the flip-flop, not "a runtime range"';
};

done_testing;
