# ABOUTME: A file lexical shared with a named sub, read at the sub's entry and then stored,
# ABOUTME: keeps the value it had on entry: $n++ returns the old value, a copy is not clobbered.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}


round_trips('my $n=0; sub f { my $x = $n++; return $x } my $a=f(); my $b=f(); print "$a $b $n\n";',
    'a post-increment copied out of a shared lexical');
round_trips('my $n=0; sub f { return $n++ } my $a=f(); my $b=f(); print "$a $b $n\n";',
    'a post-increment returned directly');
round_trips('my $n=0; sub f { my $x = $n--; return $x } my $a=f(); my $b=f(); print "$a $b $n\n";',
    'a post-decrement');
round_trips('my $n=5; sub f { my $x = $n; $n = 9; return $x } my $a=f(); print "$a $n\n";',
    'a plain copy, then a store');
round_trips('my $n=0; sub f { my $x = $n++; my $y = $n++; return "$x$y" } print f(), " $n\n";',
    'two post-increments in one sub');
round_trips('my $n=0; sub f { my $x = $n++ + 10; return $x } print f(), " ", f(), "\n";',
    'a post-increment inside an expression, the sub in list context');
round_trips('our $n=0; sub f { my $x = $n++; return $x } my $a=f(); my $b=f(); print "$a $b $n\n";',
    'the package-scalar form');
round_trips('my $n=0; my $x = $n++; print "$x $n\n";',
    'the top-level form');
round_trips('sub f { my $n = 0; my $x = $n++; return "$x $n" } print f(), "\n";',
    'a lexical of the sub itself');
round_trips('my $n=0; sub f { if ($_[0]) { return $n++ } return -1 } print f(1), f(0), f(1), " $n\n";',
    'a post-increment in a branch arm');
round_trips('my $n=0; sub f { $n = 5; my $x; if ($_[0]) { $x = $n; $n = 1 } else { $x = 2 } return $x } print f(1), f(0), " $n\n";',
    'a copy then a store, both in a branch arm, after an earlier store');
round_trips('my @a; my $n=0; sub f { my $x = $n; $n = 4; push @a, $x; return $x } f(); f(); print "@a $n\n";',
    'the copy pushed after the store');
round_trips('our $n=0; sub f { for (1..3) { $n++ } return $n } print f(), " $n\n";',
    'a void post-increment in a loop in a sub');
round_trips('our $n; my @r; for (1..3) { push @r, $n++ } print "@r $n\n";',
    'a post-increment in a top-level loop, which carries it');

# A LOOP EARLIER IN THE PROGRAM does not put the reads after it under the loop.
round_trips(q{our $n = 10; for (1..2) { } my $x = $n; $n = 3; print "$x\n";},
    q{a copy and a store after an empty loop});
round_trips(q{our $n = 10; for (1..2) { print "l" } print "a ", $n++, "\n"; print "b ", $n++, "\n";},
    q{post-increments after a loop});
round_trips(q{our $n = 10; my $i = 0; while ($i < 2) { $i++ } print "a ", $n++, "\n"; print "b $n\n";},
    q{a post-increment after a while loop});
round_trips(q{our $n=0; for (1..2) { print "l" } my $x = $n; $n = 3; print "$x\n";},
    q{a copy and a store after a loop that prints});

# IN A LOOP INSIDE A SUB, the scalar has no header Phi: the read names the
# entry memory version on every pass. A use after the body's store is refused.
sub refuses ($src, $name) {
    my $data = graph_of($src);
    ok $data, "$name: translates" or return;
    my $d = SoN::Deparse->new;
    is $d->render($data), undef, "$name: does not render";
    like $d->gap // '', qr/is read at entry and stored in a loop with no carried value/,
        "$name: the refusal names the uncarried read";
}
refuses('my $n=0; sub f { my @r; for (1..3) { push @r, $n++ } return "@r" } print f(), " $n\n";',
    'a shared lexical post-incremented in a loop, value used');
refuses('our $n=0; sub f { my @r; for (1..3) { push @r, $n++ } return "@r" } print f(), " $n\n";',
    'the package-scalar form');
refuses('my $n=0; sub f { my $s=""; for (1..3) { $s .= $n; $n += 2 } return $s } print f(), " $n\n";',
    'a read before a compound store in a loop');

# A USE THAT IS SPELLED BEFORE THE STORE is not refused: an `if` arm's merge
# takes its value in the arm, and a store before the loop is not in it.
round_trips('my $n=0; sub f { my $s = ""; for my $i (1..3) { $s .= $n if $i > 1; $n = $i } $s } print f(), " $n\n";',
    'a guarded read in a loop arm, before the store');
round_trips('my $n=0; sub f { my $s = ""; for my $i (1..3) { $s .= $n unless $i == 1; $n += $i } $s } print f(), " $n\n";',
    'an unless-guarded read, before a compound store');
round_trips('my $n=0; sub f { my $s = ""; for my $i (1..3) { $s .= $n if $i > 1; $n = $i; $s .= $n if $i > 2 } $s } print f(), " $n\n";',
    'a guarded read before the store and another after it');
round_trips('my $n=3; sub f { my $c = $n; $n = 0; my @a = (1) x $c; for (@a) { $n++ } scalar(@a) . $n } print f(), "\n";',
    'a store before the loop, a void increment in it');
round_trips('our $n=3; sub f { my $c = $n; $n = 0; my @a = (1) x $c; for (@a) { $n++ } scalar(@a) . $n } print f(), "\n";',
    'the package-scalar form of a store before the loop');
# A READ BEFORE A STORE THAT PRECEDES THE LOOP is made once, before it, and
# is bound at entry; a read at that store's version is the loop's.
round_trips('my $n=3; sub f { my $c = $n; $n = 0; for (1..$c) { $n++ } $c . $n } print f(), "\n";',
    'a copy before a store, the loop bounded by the copy');
round_trips('my $n=3; sub f { my $c = $n + 1; $n = 0; for (1..2) { $n += $c } $n } print f(), "\n";',
    'a copy before a store, added in the loop');
refuses('my $n=3; sub f { my @r; my $c = $n; $n = 0; for (1..$c) { push @r, $n++ } "@r" } print f(), " $n\n";',
    'a store before the loop, its value used in the loop');
# PAST THE LOOP'S EXIT a use is after every store in its body.
round_trips('my $n=3; sub f { my $c = $n; for (1..2) { $n++ } $c . $n } print f(), "\n";',
    'a copy at entry used after a loop that stores');
round_trips('my $n=3; sub f { my $c = $n; for (1..2) { $n++ } $c } print f(), " $n\n";',
    'a copy at entry returned after a loop that stores');
round_trips('my $n=3; sub f { my @a = (1) x $n; for (@a) { $n++ } scalar(@a) . $n } print f(), "\n";',
    'a declared array counted after a loop that stores');
refuses('my $n=0; sub f { my $s = ""; for my $i (1..3) { my $v = $n; $n = $i; if ($i > 1) { $s .= $v } } $s } print f(), " $n\n";',
    'a copy used in an arm after the store');
refuses('my $n=0; sub f { my $s = ""; for my $i (1..3) { if ($i > 1) { $s .= $n } else { $s .= "-" } $n = $i } $s } print f(), " $n\n";',
    'an if/else merged into the loop-carried value');

# A LIST ASSIGN'S VALUE READ OF A NAMED SCALAR spells like a target, and the
# renderer counted it as one: `($a, $b, $n) = (5)`. The producer says how many
# targets there are; a disagreement is refused.
sub refuses_list ($src, $name) {
    my $data = graph_of($src);
    ok $data, "$name: translates" or return;
    my $d = SoN::Deparse->new;
    is $d->render($data), undef, "$name: does not render";
    like $d->gap // '', qr/a list assign's value reads a named scalar/,
        "$name: the refusal names the value read";
}
refuses_list('my $n=1; sub f { my ($a,$b) = ($n, $n = 5); "$a-$b" } print f(), " $n\n";',
    'a list assign reading a shared lexical a later value stores');
refuses_list('my $n=1; sub f { my ($a,$b); ($a,$b) = ($n, 7); "$a-$b" } print f(), " $n\n";',
    'a list assign reading a shared lexical first');
# A SIGNATURE PARAMETER THE SUB NEVER WRITES is its name throughout, so a
# list assign reading it is safe: chalk's FilterComposite::_add_unpacked
# picks `($correct, $rejected) = ($left, $right)` or the reverse.
round_trips('use v5.42; sub f ($l, $r, $v) { my ($c, $j); if ($v) { ($c, $j) = ($l, $r) } else { ($c, $j) = ($r, $l) } return "$c>$j" } print f(1, 2, 1), f(1, 2, 0), "\n";',
    'a list assign of signature parameters');
round_trips('use v5.42; sub f ($l, $r) { my ($c, $j) = ($r, $l); $l = 9; return "$c>$j>$l" } print f(1, 2), "\n";',
    'a list assign of parameters, one written after');
# PASSED TO A CALL, a parameter lives in memory and reads as a PadAccess,
# which spells like a target. Into targets that live in memory too (passed
# on to a call, as FilterComposite passes both to `on_merge`), the targets
# are read back from memory, never as the value read, so it is safe.
round_trips('use v5.42; package O { sub m { $_[1] } } sub f ($l, $r, $v) { O->m($l); O->m($r); my ($c, $j); if ($v) { ($c, $j) = ($l, $r) } else { ($c, $j) = ($r, $l) } O->m($c, $j); return "$c>$j" } print f(1, 2, 1), f(1, 2, 0), "\n";',
    'a list assign of parameters passed to a call');
# ELEMENT READS are no named scalar, though the walk counts a Subscript as
# a target: chalk's Analysis takes `my ($lv, $val) = ($n->inputs->[0],
# $n->inputs->[1])`. The store to the container after it must not reach them.
round_trips('sub f { my $r = [[1, 2]]; my ($lv, $val) = ($r->[0][0], $r->[0][1]); $r->[0][0] = 9; return "$lv $val $r->[0][0]" } print f(), "\n";',
    'a list assign of element reads, the container written after');
round_trips('package N { sub new { bless { i => [$_[1], $_[2]] }, $_[0] } sub inputs { $_[0]{i} } } sub f { my $s = ""; for my $n (N->new(1, 2), N->new(3, 4)) { my ($lv, $val) = ($n->inputs->[0], $n->inputs->[1]); next unless $lv > 1; $s .= "$lv:$val" } $s } print f(), "\n";',
    'a list assign of elements of a call\'s result, in a loop');
# BOUND TO A TARGET WRITTEN LATER, the name would not hold the value.
{
    my $data = graph_of('sub f { my $r = [[1, 2]]; my ($lv, $val) = ($r->[0][0], $r->[0][1]); $lv = 5; return "$lv $val " . ($r->[0][0] + 1) } print f(), "\n";');
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    if (defined $out) { is run_perl($out), "5 2 2\n", 'a list assign target written later: agrees with perl' }
    else { like $d->gap, qr/read again as its target \$lv, which is written later/, 'a list assign target written later: refused' }
}
refuses_list('use v5.42; package O { sub m { $_[1] = 7 } } sub f ($l, $r) { O->m($l); my ($c, $j) = ($l, $r); O->m($l); return "$c>$j>$l" } print f(1, 2), "\n";',
    'a list assign of a parameter a call may write');
refuses_list('our $n=1; sub f { my ($a,$b) = ($n, 7); "$a-$b" } print f(), " $n\n";',
    'a list assign reading a package scalar first');
round_trips('my $n=1; sub f { my ($a,$b,$c) = (7, $n, 8); "$a-$b-$c" } print f(), " $n\n";',
    'a list assign reading a shared lexical after a constant');
round_trips('my $n=1; sub f { my ($a,$b) = ($n + 0, 7); "$a-$b" } print f(), " $n\n";',
    'a list assign reading a shared lexical in an expression');
round_trips('sub f { my ($a,$b,$c) = (undef, undef, 5); defined($a) ? 1 : $c } print f(), "\n";',
    'undef values, which the target list takes for placeholders');
round_trips('sub f { my $n = shift; my ($a,$b); ($a,$b) = ($n, 7); "$a-$b" } print f(3), "\n";',
    'a list assign reading a lexical of the sub');

# AN OPERAND PERL READS BY ALIAS sees a store a later operand of the same op
# makes: padsv pushes the variable itself, not a copy. The producer reads a
# lexical operand again once the later operands have run.
round_trips('my $n = 1; sub f { return $n . ($n = 5) } print f(), " $n\n";',
    'a concat operand stored by its right operand');
round_trips('my $n = 1; sub f { return $n + ($n = 5) } print f(), " $n\n";',
    'an add operand');
round_trips('my $n = 1; sub f { my $x = $n . ($n = 5); return $x } print f(), " $n\n";',
    'the concat copied out');
round_trips('my $n = 1; sub f { print $n, ($n = 5); print "\n" } f(); print "$n\n";',
    'print operands');
round_trips('my $n = 1; sub f { if ($_[0]) { return $n . ($n = 5) } 0 } print f(1), " $n\n";',
    'in a branch arm');
round_trips('my $n = 1; sub f { my $s = sprintf "%s%s", $n, ($n = 5); $s } print f(), " $n\n";',
    'sprintf operands');
round_trips('my $n = 1; sub f { my @r; push @r, $n, ($n = 5); "@r" } print f(), " $n\n";',
    'push operands');
round_trips('my $n = 1; sub f { $n = 2; my $x = $n . ($n = 5); return $x } print f(), " $n\n";',
    'after an earlier store');
round_trips('my $n = 1; sub f { return $n . ($n += 5) } print f(), " $n\n";',
    'stored by a compound assignment');
round_trips('my $n = 1; sub f { return $n x ($n = 3) } print f(), " $n\n";',
    'a repeat count stored by its right operand');
round_trips('my $n = 1; sub f { return $n == ($n = 1) } print f(), " $n\n";',
    'a numeric comparison');
round_trips('my $n = 1; sub f { return $n . "" . ($n = 5) } print f(), " $n\n";',
    'a three-part concat');
round_trips('my $n = 1; sub f { return join ",", $n, ($n = 5) } print f(), " $n\n";',
    'join operands');
round_trips('sub f { my $n = 1; return $n . ($n = 5) } print f(), "\n";',
    'a lexical of the sub itself');
round_trips('my $n = 1; print $n . ($n = 5), "\n";',
    'the top-level form');

# A CALL IN A LATER OPERAND may store the shared lexical, and the operand
# reads it after the call.
round_trips('my $n=1; sub f { return $n . f2() } sub f2 { $n = 5; "" } print f(), " $n\n";',
    'a concat operand stored by a called sub');
round_trips('my $n=1; sub g { $n = 5; 0 } sub f { return $n + g() } print f(), " $n\n";',
    'an add operand stored by a called sub');
round_trips('my $n=1; sub g { $n = 5; "" } sub f { print $n, g(), "\n" } f();',
    'print operands, a call stores');
round_trips('my $n=1; sub g { $n = 5; "" } sub f { my $x = $n . g(); $x } print f(), " $n\n";',
    'the concat copied out, a call stores');
round_trips('my $n=1; sub g { $n = 5; 3 } sub f { return $n * g() + $n } print f(), " $n\n";',
    'a product read again after the call');
round_trips('my $n=1; sub g { $n = 5; "" } sub f { my $x = $n . g(); $n = 7; $x } print f(), " $n\n";',
    'the concat copied out, a call stores, then a store');
round_trips('my $n=1; sub g { $n = 5; "" } sub f { my $x = $n; my $y = $n . g(); "$x$y" } print f(), " $n\n";',
    'a copy at entry, then an alias read across a call');
round_trips('my $n=1; sub g { $n = 5; "" } sub f { print $n, g(), "\n"; $n = 7 } f(); print "$n\n";',
    'print operands, a call stores, then a store');
round_trips('my $n=1; sub g { $n = 5; "" } sub f { return "$n" . g() } print f(), " $n\n";',
    'an interpolation is a copy, made before the call');
round_trips('my $n = 1; sub f { my $x = $n; return $x . g() } sub g { $n = 5; "" } print f(), " $n\n";',
    'a copy of the shared lexical, then a call stores it');
round_trips('my $n = 1; sub f { my $x = $n; return $x . ($x = 5) } print f(), " $n\n";',
    'the copy stored by its right operand');

# A READ AFTER A CALL keeps the value the call left, past a later store.
round_trips('my $n=1; sub g { $n = 5 } sub f { g(); my $x = $n; $n = 7; $x } print f(), " $n\n";',
    'a copy after a call, then a store');
round_trips('my $n=1; sub g { $n = 5 } sub f { g(); my $x = $n; $n++; $x } print f(), " $n\n";',
    'a copy after a call, then an increment');

# A PACKAGE SCALAR operand is not read again, and is refused.
sub alias_refused ($src, $name) {
    my $data = graph_of($src);
    ok !( $data && $data->{methods}{"main::f"} ), "$name: f does not translate";
    like producer_stderr(), qr/read by alias.*a later operand stores it/,
        "$name: the refusal names the alias";
}
alias_refused('our $n = 1; sub f { return $n . ($n = 5) } print f(), " $n\n";',
    'the package-scalar form');

# A BRANCH CONDITION is consumed before its arm runs, and a copy before the
# store is a statement of its own: neither is an alias.
round_trips('my $n = 1; sub f { $n ? ($n = 5) : 0 } print f(), " $n\n";',
    'a condition read, its arm stores');
round_trips('my $n = 1; sub f { $n && ($n = 5) } print f(), " $n\n";',
    'a short-circuit read, its right side stores');
round_trips('my $n = 1; sub f { my $x = $n . "a"; $n = 9; return $x } print f(), " $n\n";',
    'a concat copied out, then a store');
round_trips('my $n = 1; sub f { return $n++ . ($n = 5) } print f(), " $n\n";',
    'a post-increment is a copy, not an alias');

# A DECLARATION READING AN ENTRY-BOUND READ follows the save prologue that
# binds it: the literal deferred after the read was never emitted, and
# `my @a = (1) x $z` vanished.
round_trips('my $z=3; sub f { my @a = (1) x $z; my %h; $h{a} = 1; scalar @a } print f(), "\n";',
    'a repeat count read at entry, then an unrelated store');
round_trips('my $n=1; sub f { my @a = (1) x $n; $n = 2; scalar @a } print f(), f(), "\n";',
    'a repeat count read at entry, then a store to it');
round_trips('my $n=1; sub f { my @a = (1) x $n; $n = 2; return scalar @a } print f(), f(), "\n";',
    'the return form');
round_trips('my $n=1; sub f { my $x = $n; $n = 2; my @a = (1) x $x; scalar @a } print f(), f(), "\n";',
    'a copy at entry used as the count after the store');
round_trips('my $n=1; my $z=3; sub f { my $x = $z; $n = 2; my @a = (1) x $x; scalar @a } print f(), "\n";',
    'a copy of a different shared lexical');
round_trips('my $n=1; sub f { my $c = 0; my @a = (1) x $n; $n = 2; push @a, g(); scalar @a } sub g {7} print f(), f(), "\n";',
    'the count read at entry, a call after the store');
round_trips('our $n=1; sub f { my $x = $n; $n = 2; my @a = (1) x $x; scalar @a } print f(), f(), "\n";',
    'the package-scalar form');

# A DECLARATION READING A READ BOUND AFTER A STORE is filed behind that
# binding in the store's after-list.
round_trips('our $n=1; sub f { $n = 3; my $x = $n; $n = 2; my @a = (1) x $x; scalar @a } print f(), f(), "\n";',
    'a package read between two stores, used as a count');

sub refuses_dropped ($src, $name) {
    my $data = graph_of($src);
    ok $data, "$name: translates" or return;
    my $d = SoN::Deparse->new;
    is $d->render($data), undef, "$name: does not render";
    like $d->gap // '', qr/reads a temporary bound after a store/,
        "$name: the refusal names the temporary";
}

# A STORE CAN BE THE ARITHMETIC OP ITSELF. `$n = $y + 3` compiles to
# `add[$n] TARGMY` -- no sassign -- so the alias check has to see an op
# carrying OPpTARGET_MY as a store to its targ.
for my $c (
    [ 'my $n=1; sub f { my $y = 0; $y = $n + ($n = $y + 3); $y } print f(), "|$n\n";',
      'an add stored straight into the aliased scalar' ],
    [ 'my $n=1; sub f { my $y = 0; return $n + ($n = $y + 3) } print f(), "|$n\n";',
      'the same, returned' ],
    [ 'my $n=1; sub f { my $y = 2; return $n + ($n = $y * 2) } print f(), "|$n\n";',
      'a multiply stored straight into it' ],
    [ 'my $n=1; sub f { my @a = (4); return $n + ($n = $a[0] + 1) } print f(), "|$n\n";',
      'an add over an element stored straight into it' ],
    [ 'my $n=1; sub f { my $y = 3; print $n, ($n = $y - 1), "\n" } f();',
      'a subtract stored straight into it, as print operands' ],
) {
    my ($src, $name) = @$c;
    my $data = graph_of($src);
    if ($data && !grep { /GAP/ } producer_stderr()) {
        my $d = SoN::Deparse->new;
        my $out = $d->render($data);
        if (defined $out) { is run_perl($out), run_perl($src), "$name: agrees with perl"; next }
    }
    pass "$name: refused";
}


# A CALL IS NOT A STORE TO EVERY PAD SCALAR -- only to one a reference or a
# closure reaches. These are chalk's shapes the alias refusal must leave
# alone (LLVM::Context::_lower_vardecl, IR::Node::If::set_control_in).
round_trips(q{sub f { my $r = shift; my $s = "a$r" . g($r) . " $r"; return $s } sub g { uc $_[0] } print f("x"), "\n";},
    q{a scalar read and handed to a call in one expression});
round_trips(q{package N { sub new { bless {i => $_[1]}, $_[0] } sub index { $_[0]{i} } } my %p; my $n = N->new(3); $p{ $n->index } = $n; print ref($p{3}), "\n";},
    q{a method invocant read and stored by its own key});
round_trips(q{sub f { my $v = 1; my $r = \$v; my $s = $v . g($r); return $s } sub g { ${$_[0]} = 7; "x" } print f(), "\n";},
    q{a call reaching the scalar through a reference});

done_testing;
