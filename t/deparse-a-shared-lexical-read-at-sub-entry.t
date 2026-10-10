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

# A DECLARATION READING A READ BOUND AFTER A STORE cannot be placed after it,
# so it is refused rather than dropped.
refuses_dropped('our $n=1; sub f { $n = 3; my $x = $n; $n = 2; my @a = (1) x $x; scalar @a } print f(), f(), "\n";',
    'a package read between two stores, used as a count');

sub refuses_dropped ($src, $name) {
    my $data = graph_of($src);
    ok $data, "$name: translates" or return;
    my $d = SoN::Deparse->new;
    is $d->render($data), undef, "$name: does not render";
    like $d->gap // '', qr/reads a temporary bound after a store/,
        "$name: the refusal names the temporary";
}

done_testing;
