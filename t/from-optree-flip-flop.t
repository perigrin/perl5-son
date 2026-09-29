# ABOUTME: A scalar-context `..` is the flip-flop operator: stateful, with its
# ABOUTME: state in a pad slot perl allocates per occurrence.
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

# THE STATE IS A PAD SLOT, ALLOCATED PER OCCURRENCE. Measured -- two flip-flops
# in one program get DIFFERENT slots:
#
#     flip[$:5,6]      the first
#     flip[$:12,13]    the second
#
# so the state is not global and not shared. It is an ordinary lexical the
# operator owns, which is why `.. ` can appear twice in one program and each
# keeps its own position. Confirmed behaviourally: two identical flip-flops over
# the same range both print `2 3 4`, where a shared latch would leave the second
# already tripped.
#
# THAT IS WHY THIS IS NOT NEW VOCABULARY. A flip-flop is a read and a write of a
# hidden lexical plus the two tests, which the IR can already express -- the
# refusal says it "carries state across evaluations, which a counted expansion
# does not express", and that is true of Range and false of the IR as a whole.

# NOT NEW VOCABULARY, AND MEASURED SO. The equivalent desugaring
#
#     my $state = 0;
#     for my $l (1 .. 6) {
#         if (!$state) { $state = 1 if $l == 2 }
#         if ($state)  { push @out, $l; $state = 0 if $l == 4 }
#     }
#
# ROUND TRIPS END TO END today -- translates, renders, and the emitted program
# prints `2 3 4` exactly as perl does. So the IR expresses flip-flop semantics
# already; the refusal's claim that it "carries state across evaluations, which a
# counted expansion does not express" is true of the Range NODE and false of the
# IR as a whole.
#
# WHAT THE WORK IS: a desugaring in the walker, not a node kind. The control flow
# perl builds is
#
#     a  <|> range(other->b)[$:5,6] sK/1
#     b      padsv[$l] / const 4 / eq        the CLOSE test, down ->other
#     e      flop
#     n      padsv[$l] / const 2 / eq        the OPEN test, down ->next
#     q      flip[$:5,6]                     and the state slot rides HERE
#
# so both tests are arms of the range op and `flip` names the pad slot holding
# the position. Building that means synthesising the state slot, two Ifs and the
# conditional writes -- a real construction rather than a rule, and more than I
# will start without finishing.
#
# Recorded with the desugaring verified rather than assumed, so the next attempt
# starts from a known-good target shape.
#
# BUILT 2026-09-29, as recorded here -- perigrin chose this over a FlipFlop node
# kind. The state slot is perl's own hidden pad slot (flip's targ), seeded
# undef at entry so a loop carries it through a Phi, and the tests are selects
# rather than Ifs: the operands are effect-free, so evaluating both is the same
# value. See _desugar_flip_flop. No longer TODO.
round_trips( <<'SRC', 'a flip-flop selects an inclusive window' );
my @out;
for my $l (1 .. 6) {
    push @out, $l if ($l == 2) .. ($l == 4);
}
print "@out\n";
SRC

round_trips( <<'SRC', 'two flip-flops keep separate state' );
my @a;
my @b;
for my $l (1 .. 6) { push @a, $l if ($l == 2) .. ($l == 4) }
for my $l (1 .. 6) { push @b, $l if ($l == 3) .. ($l == 5) }
print "@a | @b\n";
SRC

round_trips( <<'SRC', 'a window that never opens selects nothing' );
my @out;
for my $l (1 .. 4) {
    push @out, $l if ($l == 9) .. ($l == 10);
}
print scalar(@out), "\n";
SRC

# THE CORPUS SHAPE: inside a grep block, with array-element operands. Corpus
# 176, and the `@window` of 003.
round_trips( <<'SRC', 'a flip-flop in a grep block' );
my @on  = (0, 1, 0, 0, 0, 0);
my @off = (0, 0, 0, 0, 1, 0);
my @i   = (0, 1, 2, 3, 4, 5);
my @o = grep { $on[$_] .. $off[$_] } @i;
print "@o\n";
SRC

# ITS VALUE IS A SEQUENCE NUMBER, "E0"-marked on the evaluation that closes it,
# and "1E0" when one evaluation opens and closes it -- a truth test alone would
# not see a wrong count.
round_trips( <<'SRC', 'the flip-flop value, printed' );
my @on  = (1, 0, 0, 0, 1);
my @off = (0, 0, 1, 0, 1);
my $out = "";
for my $i (0 .. 4) { my $v = ($on[$i] .. $off[$i]); $out .= "[$v]" }
print "$out\n";
SRC

# `...` DOES NOT TEST THE RIGHT OPERAND ON THE EVALUATION THAT OPENED IT.
# Measured: flip carries OPf_SPECIAL (0x80) for `...` and not for `..`.
round_trips( <<'SRC', 'three dots differ from two' );
my @on  = (1, 0, 0);
my @off = (1, 0, 1);
my ($two, $three) = ("", "");
for my $i (0 .. 2) {
    $two   .= ($on[$i] .. $off[$i]) ? "y" : "n";
    $three .= ($on[$i] ... $off[$i]) ? "y" : "n";
}
print "$two $three\n";
SRC

# THE LIST FORM MUST BE UNDISTURBED -- it takes the counted-expansion path and
# is the regression guard. NOT todo'd: it passes today.
round_trips( <<'SRC', 'a list-context range is unchanged' );
my $n = 4;
my @q = (1 .. $n);
print scalar(@q), " @q\n";
SRC

done_testing;
