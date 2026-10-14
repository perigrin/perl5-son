# ABOUTME: A lifted sub body (anon or `my sub`) stores a string append into the lexical it
# ABOUTME: shares, is called from any package, and a refused body refuses its callers.

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
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src) {
    my $want = run_perl($src);
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {});
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "renders: $src"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, "round trips: $src"
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

sub refuses ($src, $re) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {});
    ok !defined $out, "refuses: $src" or diag $out;
    like $d->gap // '', $re, "names the cause: $src";
}

# A STRING APPEND INTO A SHARED OR CAPTURED LEXICAL is a store, not a rebind
# of this graph's scope: perl's "xy" was emitted as "x".
round_trips($_) for
    'use v5.36; my $s = "x"; my sub f { $s .= "y"; 1 } f(); print "$s\n";',
    'use v5.36; my $s = "x"; my sub f { $s .= "y"; $s } print f(), f(), "$s\n";',
    'use v5.36; my $s = "a"; my sub f { $s = $s . "b"; $s } print f(), "\n";',
    'use v5.36; my $s = "a"; sub f { $s = "b$s"; $s } print f(), "\n";',
    'use v5.36; my $s = "a"; sub g { $s } $s .= "y"; print g(), "\n";',
    'use v5.36; my $s = "x"; my $f = sub { $s = "<$s>"; 1 }; $f->(); $f->(); print "$s\n";',
    'use v5.36; my $s = "a"; my $r = \$s; $s .= "y"; print $$r, "\n";',
    'use v5.36; my $s = ""; my sub f ($k) { $s .= "[$k]" for 1..$k; } f(2); f(1); print "$s\n";';

# THE APPEND'S VALUE IS READ ONCE. The stored value feeds both the store and
# the expression around it; rendered once per consumer it appended twice:
# perl's "ax" was emitted as "axx".
round_trips($_) for
    'use v5.36; my $s = "a"; my $f = sub { print(($s .= "x"), "\n") }; $f->();',
    'use v5.36; my $s = "a"; my $f = sub { $s .= "x" }; my $v = $f->(); print "$v $s\n";',
    'use v5.36; my $s = "a"; my $f = sub { return $s .= "x" }; my $v = $f->(); print "$v $s\n";',
    'use v5.36; my $s = "a"; my $f = sub { my $v = ($s .= "x"); print "$v $s\n" }; $f->();',
    'use v5.36; my $s = "a"; my $n = 3; my $f = sub { $s .= "x$n" }; print $f->(), " $s\n";',
    'use v5.36; my $s = "a"; my $f = sub { $s .= "x"; $s .= "y" }; print $f->(), " $s\n";',
    'use v5.36; my $s = "a"; my sub f { $s .= "x" } print f(), f(), " $s\n";',
    'use v5.36; my $s = "a"; sub g { $s .= "x" } my $v = g(); print "$v $s\n";',
    'use v5.36; my $s = "a"; my $r = \$s; my $v = ($s .= "x"); print "$v $s $$r\n";';

# A CAPTURED LEXICAL READ BEFORE A LATER STORE keeps the value it read: the
# read is spelled by name, and spelled after the store it read `z` for `a`.
round_trips($_) for
    'use v5.36; my $s = "a"; my $f = sub { my $v = $s; $s = "z"; "$v $s" }; print $f->(), "\n";',
    'use v5.36; my $s = "a"; my $f = sub { $s = "q"; my $v = $s; $s = "z"; "$v $s" }; print $f->(), "\n";',
    'use v5.36; my $s = "a"; my $f = sub { my $v = ($s .= "x"); $s = "z"; "$v $s" }; print $f->(), "\n";',
    'use v5.36; my $c = 1; my $f = sub { my $v = ($c = $c + 1); print "$v $c\n" }; $f->();',
    'use v5.36; my $s = "a"; my $f = sub ($k) { my $v = $s; if ($k) { $s = "z" } "$v $s" }; print $f->(1), $f->(0), "\n";',
    'use v5.36; my $c = 0; my $f = sub { my @r; for (1..3) { push @r, $c; $c++ } "@r $c" }; print $f->(), "\n";';

# A LIFTED BODY IS DEFINED IN main, and called from under a package.
round_trips($_) for
    'use v5.36; package P { my $x = 1; my sub f { $x + 1 } print f(), "\n"; }',
    'use v5.36; package P; my $x = 1; my sub f { $x + 1 } print f(), "\n";',
    'use v5.36; package P; my @l = (3, 1, 2); my sub f { join ",", sort { $b <=> $a } @l } print f(), "\n";',
    'use v5.36; package P; my sub f { 7 } print f(), "\n";',
    'use v5.36; package P; my $f = sub { 7 }; print $f->(), "\n";';

# A REFUSED BODY IS ABSENT, and its callers refuse rather than die.
refuses('use v5.36; my $x = 1; my sub a { my sub b { $x } b() + 1 } print a(), "\n";',
    qr/a call to `main::__PROGRAM__::__ANON__:\d+:\d+`, which is not in the graph/);
refuses('use v5.36; my @a = (1, 2, 3); my sub f { $_ *= 2 for @a } f(); print "@a\n";',
    qr/a call to `main::__PROGRAM__::__ANON__:\d+:\d+`, which is not in the graph/);
refuses('use v5.36; my @a = (1, 2, 3); my sub f { $_ *= 2 for @a } sub g { f() } g(); print "@a\n";',
    qr/a call to `main::g::__ANON__:\d+:\d+`, which is not in the graph/);
refuses('use v5.36; my @a = (1, 2, 3); my $f = sub { $_ *= 2 for @a }; my @r = ($f); $r[0]->(); print "@a\n";',
    qr/a reference to the sub body `main::__PROGRAM__::__ANON__:\d+:\d+`, which is not in the graph/);

done_testing;
