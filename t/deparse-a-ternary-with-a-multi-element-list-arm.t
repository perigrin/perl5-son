# ABOUTME: A ternary whose arm is a list of several values -- `$c ? (k => $v) : ()`,
# ABOUTME: `qw(A B)` -- picks between whole lists, and round trips in list and scalar context.

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

sub emits_quietly ($src, $name) {
    my $out = SoN::Deparse->new->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}

sub refuses ($src, $why, $name) {
    graph_of($src);
    like producer_stderr(), $why, "$name: refuses by its cause";
}

# EACH ARM IS ITS WHOLE LIST. The arm pushes every value it builds, so the
# select is between two lists, not between the last value of each.
round_trips(q{for my $c (1, 0) { my @a = $c ? (1, 2) : (3, 4); print "@a\n" }},
    'two lists of two');
round_trips(q{for my $c (1, 0) { my @a = $c ? (1, 2, 3) : (4); print scalar(@a), " @a\n" }},
    'lists of different lengths');

# chalk's optional-key idiom (TypeInferenceActions, _replay_classes).
round_trips(q{sub f { my $n = shift; return { a => 1, (defined $n ? (name => $n) : ()) } }
    print join(",", sort %{f("z")}), "|", join(",", %{f()}), "\n";},
    'an optional pair in a hash constructor');

# chalk's _emit_read_slot_as: one arm a deref, the other a qw list.
round_trips(q{for my $r ([qw(X Y Z)], undef) { my %o = (r => $r);
    my @t = $o{r} ? $o{r}->@* : qw(Int Num); print "@t\n" }},
    'a deref against a qw list');

round_trips(q{for my $c (1, 0) { print $c ? ("a", "b") : "c"; print "\n" }},
    'a list arm printed');
round_trips(q{for my $c (1, 0) { my @a = (0, ($c ? (1, 2) : ()), 9); print scalar(@a), " @a\n" }},
    'nested in an outer list');

# THE CALLER'S CONTEXT. A sub's last statement carries no want flag; in
# scalar context perl's comma yields the last element, in list context all.
round_trips(q{sub g { $_[0] ? (1, 2) : ("s") } my $s = g(1); my @l = g(1); my $t = g(0);
    print "$s ", scalar(@l), " $t\n";},
    'a list arm as a sub value, scalar and list callers');

round_trips(q{sub f { wantarray ? (1, 2) : "s" } my @l = f(); my $s = f(); print scalar(@l), " $s\n";},
    'the wantarray idiom');

# SCALAR CONTEXT yields the last element, and the emission says so quietly:
# a constant ahead of it is a "Useless use of a constant" warning.
round_trips(q{my ($a, $b) = (5, 6); for my $c (1, 0) { my $x = $c ? ($a, $b) : 3; print "$x\n" }},
    'a list arm in scalar context');
emits_quietly(q{my ($a, $b) = (5, 6); for my $c (1, 0) { my $x = $c ? ($a, $b) : 3; print "$x\n" }},
    'a list arm in scalar context');

# A COUNT OF THE LIST is the number of elements, not the last one.
round_trips(q{for my $c (1, 0) { my $n = () = ($c ? (7, 8, 9) : ()); print "$n\n" }},
    'counted through an empty list assign');

# AN ARM THAT CALLS OR ALLOCATES merges through a Phi, built as a branch so
# the call runs only in its arm. In LIST context the Phi is the arm's list.
round_trips(q{sub k { print "k\n"; 3 } for my $c (1, 0) { my @a = $c ? (k(), 4) : (); print scalar(@a), " @a\n" }},
    'a list arm with a call');
round_trips(q{sub k { print "k\n"; 3 } for my $c (1, 0) { my @a = $c ? (k(), 4) : (5, 6, 7); print "@a\n" }},
    'two list arms, one with a call');
# chalk's _extract_fields: an optional pair whose value is a method call.
round_trips(q{package N { sub new { bless { v => $_[1] }, $_[0] } sub value { $_[0]{v} } }
    sub f { my $n = shift; return { k => 1, (defined $n->value ? (value => "${\$n->value}") : ()) } }
    for my $v (7, undef) { my $h = f(N->new($v)); print join(",", map { "$_=$h->{$_}" } sort keys %$h), "\n" }},
    'an optional pair with a method call in a hash constructor');
round_trips(q{for my $c (1, 0) { my @a = $c ? (1, 2) : [3]; print scalar(@a), "\n" }},
    'a list arm beside an allocating arm, in list context');

# A COUNT OF THAT PHI is the number of elements in the chosen arm, not 1: the
# merged value is a list, and counting it as one scalar folded to a constant.
round_trips(q{for my $c (1, 0) { my $n = () = $c ? ([1], [2], [3]) : (); print "$n\n" }},
    'a counted list arm that allocates');
round_trips(q{sub k { print "k\n"; 3 } for my $c (1, 0) { my $n = () = $c ? (k(), 4) : (); print "$n\n" }},
    'a counted list arm that calls');
round_trips(q{sub k { 3 } for my $c (1, 0) { my $n = () = $c ? (k(), k()) : (k()); print "$n\n" }},
    'counted list arms that both call');
round_trips(q{for my $c (1, 0) { my $n = (() = $c ? ([1], 2) : ()) + 0; print "$n\n" }},
    'a counted list arm in arithmetic');
round_trips(q{for my $c (1, 0) { print((() = $c ? ([1], [2]) : ()) == 2 ? "two\n" : "not\n") }},
    'a counted list arm compared');
round_trips(q{for my $c (1, 0) { my $n = () = ($c ? (1, 2) : ()); my $m = () = ($c ? ([1], 2) : ()); print "$n $m\n" }},
    'a constant and an allocating list arm counted side by side');

# SCALAR CONTEXT keeps only the last value. Anything ahead of it ran for its
# effects, which are already on the memory chain; spelled again it is a
# "Useless use" warning, whatever kind of node it is.
for my $src (q{my @x = (1, 2, 3); for my $c (1, 0) { my $n = $c ? (@x, 9) : 1; print "$n\n" }},
             q{my $i = 0; for my $c (1, 0) { my $x = $c ? ($i++, 7) : 8; print "$x $i\n" }},
             q{my $i = 0; for my $c (1, 0) { my $x = $c ? ($i++, $i++, $i) : 8; print "$x $i\n" }},
             q{sub k { print "k\n"; 3 } for my $c (1, 0) { my $x = $c ? (k(), 7) : 8; print "$x\n" }}) {
    round_trips($src, "scalar context: $src");
    emits_quietly($src, "scalar context: $src");
}

# STILL REFUSED: in the CALLER'S context the merged list would be read as a
# count by a scalar caller, where perl's comma yields the last element.
refuses(q{sub f { wantarray ? (7, 8) : [] } my @a = f(); print "@a\n";},
    qr/GAP: a ternary with a multi-element list arm not yet lowered/,
    'a list arm beside an allocating arm, in the caller\'s context');
refuses(q{my @a = (0); for my $c (1, 0) { my @r = ($c ? (($a[0] = 1), 2) : 3); print "@r @a\n" }},
    qr/GAP: a ternary with a multi-element list arm not yet lowered/,
    'a list arm that stores an element');

# AN ARRAY ASSIGNED A LIST-VALUED TERNARY IS STILL AN ARRAY. Bound as the
# ternary itself, a later push was spelled on the expression (`push((c ? ..),
# 4)`, which perl rejects) and a reference took the ternary's value.
for my $src (
    q{for my $c (1, 0) { my @a = $c ? (1, 2) : (3); push @a, 4; print "@a\n" }},
    q{for my $c (1, 0) { my @a = $c ? (1) : (); push @a, 4; print "@a\n" }},
    q{for my $c (1, 0) { my @a = $c ? (1, 2) : (3); pop @a; print "@a\n" }},
    q{for my $c (1, 0) { my @a = $c ? (1, 2) : (3); unshift @a, 0; print "@a\n" }},
    q{for my $c (1, 0) { my @a = $c ? (1, 2) : (3); splice @a, 0, 1; print "@a\n" }},
    q{for my $c (1, 0) { my @x = (5, 6); my @a = $c ? @x : (3); push @a, 4; print "@a\n" }},
    q{for my $c (1, 0) { my @a = $c ? (1, 2) : (3); my $r = \@a; push @$r, 5; print "@a\n" }},
    q{for my $c (1, 0) { my @a = $c ? (1, 2) : (3); print scalar(@a), " @a\n" }},
) {
    round_trips($src, "an array of a list arm: $src");
}

# A STORE TO AN ARRAY'S LAST INDEX truncates or extends it. It reaches the
# graph as a value (`Count - 1`), not a store, and was dropped silently.
for my $src (
    q{for my $c (1, 0) { my @a = $c ? (1, 2) : (3); $#a = 0; print "@a\n" }},
    q{my @a = (0, 1); $#a = 0; print "@a\n";},
    q{my @a = (0, 1); $#a++; print scalar(@a), "\n";},
    q{my $r = [1, 2, 3]; $#$r = 0; print "@$r\n";},
) {
    refuses($src, qr/GAP: a store to an array's last index/,
        "\$#a as a target: $src");
}

# A PACKAGE OR SHARED ARRAY BOUND TO A WHOLE VALUE IS STORED, as one bound to
# a literal is: a sub reading @g sees it.
for my $src (
    q{our @g; sub sg { scalar @g } for my $c (1, 0) { @g = $c ? (1, 2) : (); print sg(), "\n" }},
    q{our @g; sub sg { scalar @g } for my $c (1, 0) { @g = $c ? (1) : (); print sg(), "\n" }},
    q{my @g; sub sg { "@g" } for my $c (1, 0) { @g = $c ? (1, 2) : (); print sg(), "\n" }},
    q{our @g; sub sg { scalar @g } my $i = 0; while ($i < 2) { @g = (1, $i); $i++; print sg(), "\n" }},
    q{our @g; sub sg { "@g" } my @x = (1, 2); @g = map { $_ * 2 } @x; print sg(), "\n";},
    q{our @g; sub sg { "@g" } my %h = (a => 1); @g = keys %h; print sg(), "\n";},
) {
    round_trips($src, "a stored aggregate: $src");
}

# COUNTING A CALL counts what it returns in list context, not one.
for my $src (
    q{sub g { $_[0] ? (1, 2, 3) : () } my $n = () = g(1); my $m = () = g(0); print "$n $m\n";},
    q{sub g { $_[0] ? (1) : () } my $n = () = g(1); my $m = () = g(0); print "$n $m\n";},
    q{sub g { (1, 2) } my $n = () = g(); print "$n\n";},
    q{sub g { print "g\n"; (1, 2) } my $n = () = (g(), 5); print "$n\n";},
) {
    round_trips($src, "a counted call: $src");
}

# AN ELEMENT READ IN A LIST IS READ WHERE THE LIST IS. Spelled again at each
# read of the array it was copied into, it saw the store made after the copy.
for my $src (
    q{my $c = 1; my %h = (k => 1); my @b = $c ? ($h{k}, 5) : (); $h{k} = 9; print "@b\n";},
    q{my $c = 1; my @a = (1, 2); my @b = $c ? ($a[0], 5) : (); $a[0] = 9; print "@b\n";},
    q{my $c = 1; my @a = (1, 2); my $r = \@a; my @b = $c ? ($r->[0], 5) : (); $r->[0] = 9; print "@b\n";},
    q{my $c = 1; my @a = (1, 2); my @b = $c ? ($a[0], $a[1]) : (); $a[0] = 9; print "@b @a\n";},
    q{my $c = 1; my @a = (1, 2); my @b = $c ? ($a[0]) : (); $a[0] = 9; print "@b\n";},
    q{my @a = (1, 2); my @b = ($a[0], $a[1]); $a[0] = 9; print "@b\n";},
    q{my %h = (k => 1); my @b = ($h{k}, 5); $h{k} = 9; print "@b\n";},
    q{my @a = (1, 2); sub f { $_[0] = 3 } f($a[0], 5); my @b = ($a[0]); $a[0] = 9; print "@a @b\n";},
    q{my @a = (1, 2); my $r = [$a[0], 5]; $a[0] = 9; print "@$r\n";},
) {
    round_trips($src, "an element read copied: $src");
}

# A MATCH IN A LIST ARM is an effect (pos(), $1) and a read of its subject
# at one point. Neither is pinned inside an arm, so it is refused there.
for my $src (
    q{my $c = 1; my $s = "xax"; my $x = $c ? ($s =~ /x/g, 7) : 1; print $x, " ", pos($s) // 'u', "\n";},
    q{my $c = 1; my $s = "xax"; my @x = $c ? (scalar($s =~ /x/g), 7) : 1; print "@x ", pos($s) // "u", "\n";},
    q{my $c = 1; my $s = "xax"; my @x = $c ? (7, $s =~ /(x)/) : 1; print "@x $1\n";},
    q{sub k { 3 } my $c = 1; my @x = $c ? (k() =~ /3/, 7) : (); print "@x\n";},
) {
    refuses($src, qr/GAP: a regex match in a multi-element ternary arm is not yet lowered/,
        "a match in a list arm: $src");
}

# A REFERENCE TO $#a can write through it, which a Count cannot take; it is
# refused by its own name, not as the store it may never make.
for my $src (
    q{my @a = (1, 2); my $r = \$#a; print "$$r\n";},
    q{my @a = (1, 2); my $r = \$#a; $$r = 0; print "@a\n";},
    q{my @a = (1, 2); for my $x (\$#a) { print "$$x\n" }},
    q{my @a = (1, 2); my @r = \($#a, 1); print "${$r[0]}\n";},
) {
    refuses($src, qr/GAP: a reference to an array's last index/,
        "a reference to \$#a: $src");
}
for my $src (
    q{my @a = (1, 2); print $#a, "\n";},
    q{my $r = [1, 2]; print $#$r, "\n";},
    q{my @a = (1, 2, 3); print join(",", 0 .. $#a), "\n";},
) {
    round_trips($src, "\$#a read: $src");
}

# A TERNARY ARGUMENT PASSES ITS ARMS' VARIABLES BY ALIAS, as a direct argument
# does: the callee writes them through @_, a reference to the list refers to
# each, and foreach and map alias $_ to them. A list arm is an anonymous list
# of copies, so the write vanished or died on a read-only constant. Refused.
for my $src (
    q{sub g { $_[1] = 42 } my $c = @ARGV ? 0 : 1; my $s = time % 1 + 5; my $t = $s + 1; g($c ? ($s, $t) : ()); print "$s $t\n";},
    q{sub g { $_[1] = 42 } my $c = 1; my $s = 5; my $t = 6; g($c ? ($s, $t) : ()); print "$s $t\n";},
    q{sub g { my @x = @_; $_[0] = 9; "@x" } my $c = 1; my $s = 5; my $r = g($c ? ($s, 6) : ()); print "$r $s\n";},
    q{sub g { $_[1] = 42; 0 } my $s = 5; my $t = 6; for my $c (1, 0) { g($c ? ($s, $t) : ($t, $s)) } print "$s $t\n";},
    q{sub g { $_[0] = 42 } my $c = 1; my $s = 5; g($c ? $s : ()); print "$s\n";},
    q{sub g { $_[0] = 42 } my $s = 5; for my $c (1, 0) { g($c ? $s : ()) } print "$s\n";},
    q{sub k { 7 } sub g { $_[0] = 42 } my $s = 5; for my $c (1, 0) { g($c ? ($s, k()) : ()) } print "$s\n";},
    q{sub g { $_[0] = 1 } our $s = 5; my $c = 1; g($c ? ($s, 2) : ()); print "$s\n";},
    q{sub g { $_[0] = 1 } my @a = (5, 6); my $c = 1; g($c ? (@a) : ()); print "@a\n";},
    q{sub g { $_[0] = 1 } my %h = (a => 5); my $c = 1; g($c ? ($h{a}, 2) : ()); print "$h{a}\n";},
    q{my $c = 1; my $s = 5; my $t = 6; my @r = \($c ? ($s, $t) : ()); ${$r[1]} = 0; print "$s $t\n";},
    q{my $c = 1; my $s = 5; my $t = 6; for ($c ? ($s, $t) : ()) { $_ = 7 } print "$s $t\n";},
    q{my $s = 5; my $t = 6; for my $c (1, 0) { $_++ for ($c ? ($s, $t) : ($t)) } print "$s $t\n";},
    q{my $c = 1; my $s = 5; my $t = 6; my @r = map { $_ *= 2 } ($c ? ($s, $t) : ()); print "@r $s $t\n";},
) {
    refuses($src, qr/GAP: a ternary list arm passed by alias/,
        "an aliased ternary list arm: $src");
}
# Constants and expressions are temporaries: nothing to alias, so they lower.
for my $src (
    q{sub g { "@_" } for my $c (1, 0) { print g($c ? (1, 2) : ()), "\n" }},
    q{sub g { "@_" } my $s = 4; for my $c (1, 0) { print g($c ? ($s + 1, 2) : (3)), "\n" }},
) {
    round_trips($src, "a ternary argument of temporaries: $src");
}

# AN ARRAY ASSIGNMENT IN SCALAR CONTEXT IS ITS COUNT, whichever path built the
# array: a ternary of lists makes a literal, which printed its elements.
for my $src (
    q{my $c = 1; print scalar(my @t = $c ? (7) : ()), "\n";},
    q{my $c = 1; my @t; print scalar(@t = $c ? (1, 2, 3) : ()), "\n";},
    q{my $c = 0; print scalar(my @t = $c ? (1, 2, 3) : ()), "\n";},
    q{my $c = time; print scalar(my @t = (1, 2, $c)), "\n";},
    q{my $c = 1; my @t; print 0 + (@t = $c ? (5, 6) : (7)), " @t\n";},
    q{sub f { my $c = shift; return scalar(my @t = $c ? (1, 2) : ()) } print f(1), f(0), "\n";},
) {
    round_trips($src, "an array assignment counted: $src");
}
refuses(q{my $c = 1; my %h; print scalar(%h = $c ? (a => 1) : ()), "\n";},
    qr/GAP: a hash assignment from a ternary counted in scalar context/,
    'a hash assignment from a ternary counted');

# AN ARRAY OF A LIST ARM IS READ AS THE ARRAY. Its elements were spelled again
# as the ternary at the read, after a store to what the arm copied.
for my $src (
    q{my $c = 1; my @a = (time % 1 + 1, 2); my @b = $c ? ($a[0], 3) : (); $a[0] = 9; print "@b\n";},
    q{my $c = 1; my %h = (k => time % 1 + 1); my @b = $c ? ($h{k}, 5) : (); $h{k} = 9; print "@b\n";},
    q{my @a = (time % 1 + 1, 2); for my $c (1, 0) { my @b = $c ? ($a[0], 3) : (4, 5); $a[0] = 9; print "@b\n" }},
    q{my $c = 1; my @a = (time % 1 + 1, 2); my @b = $c ? ($a[0], 3) : (); $a[0] = 9; my @d = @b; print "@d\n";},
    q{my $x = time % 1 + 1; my $c = 1; my @b = $c ? ($x, 3) : (); $x = 9; print "@b\n";},
) {
    round_trips($src, "a copied list arm read as its array: $src");
}

# A CLASS FIELD FIRST READ IN ONE ARM is the field on both paths. Merged with
# undef, `$f[0] = 5` after the ternary stored through `($c ? @f : undef)`.
for my $src (
    q{use feature "class"; no warnings; class P { field @f = (1, 2); method m { my $c = 1; my @b = $c ? ($f[0], 2) : (); $f[0] = 5; return "@b" } } print P->new->m, "\n";},
    q{use feature "class"; no warnings; class P { field %f = (k => 1); method m { my $c = 1; my @b = $c ? ($f{k}, 2) : (); $f{k} = 5; return "@b" } } print P->new->m, "\n";},
    q{use feature "class"; no warnings; class P { field @f = (1, 2); method m { my $c = 1; my @b = $c ? ($f[0]) : (); $f[0] = 5; return "@b" } } print P->new->m, "\n";},
    q{use feature "class"; no warnings; class P { field @f = (1, 2); method m ($c) { my $b = $c ? $f[1] : 3; $f[0] = 5; return "$b @f" } } print P->new->m(0), P->new->m(1), "\n";},
    q{my @a = (1, 2); sub f { my $c = shift; my $b = $c ? $a[0] : 3; $a[1] = 7; "$b @a" } print f(1), f(0), "\n";},
) {
    round_trips($src, "a field first read in an arm: $src");
}

# A CLASS FIELD'S WHOLE VALUE in a list arm has no memory version, so it is
# spelled after a later store to the field. Refused by name.
for my $src (
    q{use feature "class"; no warnings; class P { field $x = 1; method m ($c) { $x = 3; my @b = $c ? ($x, 2) : (3); $x = 5; return "@b $x" } } print P->new->m(0), P->new->m(1), "\n";},
    q{use feature "class"; no warnings; class P { field $x = 1; method m ($c) { $x = 3; my @b = $c ? ($x + 1, 2) : (3); $x = 5; return "@b $x" } } print P->new->m(0), P->new->m(1), "\n";},
    q{use feature "class"; no warnings; class P { field @f = (1); method m ($c) { push @f, 3; my @b = $c ? (@f, 2) : (3); push @f, 5; return "@b @f" } } print P->new->m(0), P->new->m(1), "\n";},
) {
    refuses($src, qr/GAP: a class field read in a multi-element ternary arm/,
        "a field read in a list arm: $src");
}

# PRINT SEPARATES ITS LIST WITH $, as perl's does.
for my $src (
    q{my $c = 1; local $, = "-"; print $c ? (1, 2) : (3); print "\n";},
    q{local $, = "-"; my @x = (1, 2); print @x; print "\n";},
    q{local $, = ","; print 1, 2, 3; print "\n";},
    q{local $, = ","; local $\ = "!\n"; print 1, 2;},
    q{print 1, 2, "\n";},
    q{local $, = ":"; print STDOUT "a", "b"; print "\n";},
) {
    round_trips($src, "print with \$,: $src");
}

done_testing;
