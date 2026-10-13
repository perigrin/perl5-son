# ABOUTME: A lexical sub defined at file scope closes over the file's lexicals as a named sub
# ABOUTME: does: lifted, it reads them by name, and a lexical sub inside a sub still refuses.

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


# The emission must also be QUIET: a second `my @e` in one scope is a "masks
# earlier declaration" warning, and the masked variable is the defect.
sub emits_quietly ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}


round_trips('use v5.36; my $n = 10; my sub add ($x) { $x + $n } print add(1), add(2), "\n";',
    'a lexical sub closing over a file lexical, called at top level');
round_trips('use v5.36; my $k = 3; my sub a ($x) { $x + $k } sub g { a(1) } print g(), "\n";',
    'a lexical sub closing over a file lexical, called from a named sub');
# chalk's TypeInferenceActions: a predicate held in a class-block lexical,
# passed on by `my sub`s that the methods call.
round_trips('use v5.36; use experimental "class"; class C { my $p = sub ($n) { $n * 2 }; my sub f ($x) { $p->($x) } method m ($v) { f($v) } } print C->new->m(4), "\n";',
    'a lexical sub closing over a class-block lexical, called from a method');
round_trips('use v5.36; my $c = 0; my sub bump () { $c++ } bump(); bump(); sub g { bump(); $c } print g(), " $c\n";',
    'a lexical sub writing the file lexical it closes over');
round_trips('use v5.36; my $p = sub ($n) { $n > 1 }; my sub f ($x) { $p->($x) ? "big" : "small" } sub g { f(shift) } print g(1), g(5), "\n";',
    'a lexical sub calling a code reference it closes over');

# A LEXICAL SUB DEFINED INSIDE A SUB closes over that sub's lexicals, which
# have no name at file scope: still refused.
graph_of('use v5.36; sub g ($m) { my sub a ($x) { $x + $m } a(1) } print g(2), "\n";');
like producer_stderr(), qr/a lexical sub closing over \$m is not yet lowered/,
    'a lexical sub closing over a lexical of the sub it is defined in refuses';

# BY NAME IS ONE VARIABLE PER NAME, and these have several: a shadowing
# declaration, and a `my sub` cloned once per pass of a loop.
for my $case (
    [ 'use v5.36; my $x = 1; my sub a { $x } { my $x = 2; my sub b { $x } print a(), b(), "\n"; }',
      qr/a lexical sub closing over \$x is not yet lowered -- the file declares that name more than once/ ],
    [ 'use v5.36; my @r; for my $i (1..3) { my $j = $i * 10; my sub h { $j } push @r, \&h; } print join(",", map { $_->() } @r), "\n";',
      qr/a lexical sub closing over \$j is not yet lowered -- it is cloned inside a loop/ ],
    [ 'use v5.36; my @r; my $i = 0; do { my $j = ++$i; my sub h { $j } push @r, \&h } while ($i < 3); print join(",", map { $_->() } @r), "\n";',
      qr/a lexical sub closing over \$j is not yet lowered -- it is cloned inside a loop/ ],
    [ 'use v5.36; my @r = map { my $j = $_; my sub h { $j } \&h } 1..3; print join(",", map { $_->() } @r), "\n";',
      qr/a lexical sub closing over \$j is not yet lowered -- it is cloned inside a loop/ ],
) {
    graph_of($case->[0]);
    like producer_stderr(), $case->[1], "refuses: $case->[0]";
}

# AN APPEND TO AN UNDEFINED VARIABLE IS QUIET: perl's `.=` treats undef as
# the empty string without a warning, where `.` warns. The chalk shape is a
# class-block lexical declared with no initializer and appended to in a
# `my sub`.
for my $src (
    'use v5.36; my $s; my sub f { $s .= "a" } f(); print "$s\n";',
    'use v5.36; my $s; my sub f { $s } $s .= "a"; print f(), "\n";',
    'use v5.36; my $s; my sub f { $s .= "a$_" for 1..2 } f(); print "$s\n";',
    'use v5.36; my $s; my $t = "q"; my sub f { $s .= $t } f(); f(); print "$s\n";',
    'use v5.36; my $s; my sub f ($x) { $s .= "<$x>" } f(1); f(2); sub g { $s } print g(), "\n";',
    'use v5.36; use experimental "class"; class C { my $s; my sub app { $s .= "b" } method m { app(); $s } } print C->new->m, "\n";',
) {
    round_trips($src, "appends: $src");
    emits_quietly($src, "appends: $src");
}

# A CLOSURE BUILT ONCE PER PASS captures that pass's variable -- a `my` in the
# loop body, or the foreach variable -- and lifted, its body reads one
# variable by name: every closure read the last pass (perl's 2 became 3).
for my $src (
    'use v5.36; my @a; for my $i (1..3) { my $j = $i; push @a, sub { $j } } my sub f { $a[1]->() } print f(), "\n";',
    'use v5.36; my @a; for my $i (1..3) { push @a, sub { $i } } my sub f { $a[1]->() } print f(), "\n";',
    'use v5.36; my @a; my sub f { $a[1]->() } for my $i (1..3) { my $j = $i; push @a, sub { $j } } print f(), "\n";',
    'use v5.36; my @a; for my $i (1..3) { my $j = $i; push @a, sub { $j } } print $a[1]->(), "\n";',
    'use v5.36; sub g { my @a; for my $i (1..3) { my $j = $i; push @a, sub { $j } } $a[1]->() } print g(), "\n";',
    'use v5.36; my @a; my $i = 0; while ($i < 3) { my $j = ++$i; push @a, sub { $j } } print $a[0]->(), "\n";',
    'use v5.36; my @a = map { my $j = $_; sub { $j } } 1..3; print $a[0]->(), "\n";',
) {
    graph_of($src);
    like producer_stderr(), qr/an anonymous sub closing over \S+ is not yet lowered -- it is built once per pass of a loop/,
        "refuses: $src";
}

# A variable declared OUTSIDE the loop is one variable for every pass, and a
# closure over it is still lowered.
round_trips('use v5.36; my @a; my $k = 0; for my $i (1..3) { $k += $i; push @a, sub { $k } } print $a[0]->(), "\n";',
    'closures in a loop over a variable declared outside it');
round_trips('use v5.36; sub g { my @a; my $k = 5; for (1..3) { push @a, sub { $k } } $a[2]->() } print g(), "\n";',
    'closures in a loop in a sub over its lexical declared outside the loop');

done_testing;
