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

# RANGE IS A BRANCH OP REACHED BEFORE ITS OPERANDS, and which arm holds which
# bound is measured, not assumed:
#
#     7  <|> range(other->8)[$:2,3] lK/1 ->e
#     e      <$> const[IV 1] s               the LOW bound, down ->next
#     8      <0> padsv[$n:1,3] s             the HIGH bound, down ->other
#
# So each arm is walked with _walk_branch, the way every other branch op walks
# an arm onto the stack. Walking `first`/`sibling` instead left an extra value
# behind and the enclosing ArrayLiteral came out `in=[Range, Constant]`,
# holding a bound beside the list.
#
# A `foreach` over a runtime range never reaches this handler: perl OPTIMISES
# THE RANGE AWAY there, leaving the bounds as plain ops before enteriter, which
# is why _translate_foreach_range receives them already on the stack.
subtest 'a list-context runtime range expands' => sub {
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

# THE SPLIT STILL HOLDS, from the other side now. The scalar form was refused
# under its own name; it is lowered since 2026-09-29 (a state slot plus selects,
# _desugar_flip_flop), so the pin is that it ROUND-TRIPS as a flip-flop -- and
# that the list form is not mistaken for one.
round_trips(
    'my $x = 3; my $r = (($x==1)..($x==5)) ? "y" : "n"; print "$r\n";',
    'the scalar-context flip-flop round-trips as a flip-flop' );

subtest 'the list form is not a flip-flop' => sub {
    my ( $data, $lerr ) = graph_of('my $n=3; my @q=(1..$n); print "@q\n";');
    unlike $lerr, qr/flip-flop/, 'a list range is not called a flip-flop';
    ok $data && $data->{methods}{'main::__PROGRAM__'}, '... and it translates';
};

done_testing;
