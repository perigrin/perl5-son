# ABOUTME: A foreach over a bare-declared array or a $_/package-iterated deref lowers only
# ABOUTME: a body that reaches the list through its iterator alone; anything else refuses by name.

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


sub refuses_render ($src, $cause, $name) {
    my $data = graph_of($src);
    is producer_stderr(), '', "$name: the producer says nothing";
    my $d = SoN::Deparse->new;
    my $out = $data ? $d->render($data) : undef;
    ok !defined $out, "$name: the renderer refuses";
    like $d->gap // '', $cause, "$name: naming its cause";
}


sub refuses ($src, $cause, $name) {
    graph_of($src);
    like producer_stderr(), $cause, "$name: refused, naming its cause";
}

# THE LIST IS UNPROVEN: a bare-declared `my @a`, or `@$r` under `$_` or a
# package iterator, which the array path takes without a typed binding. The
# lowering binds the iterator to an index read, so it is right only when the
# body cannot see or change the list except through the iterator. A call, a
# shift, an element store, a nested map, grep or foreach, or an iterator write
# next to an array read each broke it; the body is refused instead.
my $UNPROVEN = qr/GAP: a foreach over an unproven list .* whose body may reach the list other than through its iterator/;
# A TYPED ARRAY keeps the array path it had, and the renderer refuses a read
# carried past a later store to the same aggregate.
my $STALE = qr/GAP: an element read in a loop is spelled after a store/;

# An iterator write, then an element store, then a read of the iterator.
refuses_render(q{sub f { my @a = (1,2); my $s=""; for my $x (@a) { $x .= "y"; $a[0] = "q"; $s .= $x } print "$s|@a\n" } f();},
    $STALE, 'a typed array: an alias write, an element store, an alias read');
refuses(q{sub f { my @a; push @a, 1, 2; my $s=""; for my $x (@a) { $x .= "y"; $a[0] = "q"; $s .= $x } print "$s|@a\n" } f();},
    $UNPROVEN, 'a bare array: an alias write, an element store, an alias read');
refuses_render(q{sub f { my @a = (1,2); my $r = \@a; my $s=""; for my $x (@a) { $x .= "y"; $r->[0] = "q"; $s .= $x } print "$s|@a\n" } f();},
    $STALE, 'a typed array: the element store through a reference');
refuses(q{sub f { my @a; push @a, 1, 2; my $r = \@a; my $s=""; for my $x (@a) { $x .= "y"; $r->[0] = "q"; $s .= $x } print "$s|@a\n" } f();},
    $UNPROVEN, 'a bare array: the element store through a reference');
refuses(q{use v5.42; sub f($r) { my $s=""; for (@$r) { $_ .= "y"; $r->[0] = "q"; $s .= $_ } "$s|@$r" } print f([1,2]), "\n";},
    $UNPROVEN, 'a topic deref: the element store through the reference');

# A read of the iterator on both sides of an element store.
# NOW LOWERED: the iterator is aliased by reference -- see
# t/deparse-a-foreach-alias-is-a-reference.t.
round_trips(q{sub f { my @a = (1,2); my $s = ""; for my $x (@a) { $s .= sprintf("%s", $x); $a[0] = 9; $s .= "$x" } print "$s\n" } f();},
    'a typed array: a read, an element store, a read');
round_trips(q{sub f { my @a; push @a, 1, 2; my $s = ""; for my $x (@a) { $s .= sprintf("%s", $x); $a[0] = 9; $s .= "$x" } print "$s\n" } f();},
    'a bare array: a read, an element store, a read');
round_trips(q{sub f { my @a; push @a, 1, 2; my $s = ""; for my $x (@a) { $s .= "$x"; $a[0] = 9; $s .= "$x" } print "$s\n" } f();},
    'a bare array: two interpolated reads around an element store');
refuses(q{use v5.42; sub f($r) { my $s = ""; for (@$r) { $s .= $_; $r->[0] = 9; $s .= $_ } $s } print f([1,2]), "\n";},
    $UNPROVEN, 'a topic deref: two reads around an element store');

# A HASH ELEMENT IS NOT AN ARRAY ELEMENT, so a store into one is safe -- but
# it must reach memory past the loop, and the push before it must be a memory
# version: the post-loop read was bound ahead of the push (`12|1`).
round_trips(q{sub f { my %h = (a => 1); my @a; push @a, 1, 2; my $s=""; for my $x (@a) { $h{a} = 9; $s .= $x } print "$s|$h{a}\n" } f();},
    'a bare array: a constant-key hash store, read after the loop');
# A READ OF THE SAME ELEMENT in the body was one node with the read after
# the loop, in every loop form (`2` for perl's `3`), and refused. The loop
# carries its memory through its exit now, and the read after it is its own.
round_trips(q{sub f { my %h = (a => 1); my @a; push @a, 1, 2; my $s=""; for my $x (@a) { $h{a}++; $s .= $x } print "$s|$h{a}\n" } f();},
    'a bare array: a hash increment, read after the loop');
round_trips(q{sub f { my %h = (a => 1); my @a; push @a, 1, 2; for my $x (@a) { $h{a} .= $x } print "$h{a}\n" } f();},
    'a bare array: a hash append, read after the loop');
round_trips(q{sub f { my %h; my @a; push @a, 1, 2; for my $x (@a) { $h{$x} = 9 } print join(",", map { "$_=$h{$_}" } sort keys %h), "\n" } f();},
    'a bare array: a hash store keyed by the iterator');
round_trips(q{sub f { my %h = (a => 1); my @a = (1, 2); my $s=""; for my $x (@a) { $h{a} = 9; $s .= $x } print "$s|$h{a}\n" } f();},
    'a typed array: a constant-key hash store, read after the loop');
round_trips(q{sub f { my %h = (a => 1); my @a; push @a, 1, 2; my $s=""; for my $x (@a) { next if $x == 5; $h{a} = 9; $s .= $x } print "$s|$h{a}\n" } f();},
    'a bare array: a guarded hash store, read after the loop');
round_trips(q{our $g; sub f { $g = 9; my @a; push @a, 1, 2; print "$a[0]|$g\n" } f();},
    'a push onto a bare array after a store, read outside any loop');
# NOT FOREACH ALONE: a read of a loop's memory after the loop happens at its
# exit, wherever an earlier store or push sits.
round_trips(q{sub f { my %h = (a => 1); my @a = (1); push @a, 2; my $k = 0; while ($k++ < 2) { $h{a} = 9 } print "$h{a}\n" } f();},
    'a while: a hash store after a push, read after the loop');
round_trips(q{sub f { my %h = (a => 1); my @a = (1); push @a, 2; my $k = 0; while ($k++ < 2) { $h{a} = 9 } my $z = $h{a}; $h{a} = 3; print "$z|$h{a}\n" } f();},
    'a while: a read after the loop, then a store');

# A NESTED map, grep OR foreach over ANOTHER list, inside one no call can
# reach: it aliases only its own list's elements, and under `$_` it
# localises the outer iterator and restores it -- measured, each
# round-trips. One over the outer list still refuses (per-pass tests).
round_trips(q{sub f { $_ = 9; my @a; push @a, 1, 2; my @c = (3); my $s = ""; for (@a) { my @b = map { $_ * 2 } @c; $s .= "$_@b" } print "$s|$_\n" } f();},
    'a bare array under $_: a nested map');
round_trips(q{sub f { $_ = 9; my @a; push @a, 1, 2; my @c = (3); my $s = ""; for (@a) { my @b = grep { $_ > 1 } @c; $s .= "$_@b" } print "$s|$_\n" } f();},
    'a bare array under $_: a nested grep');
round_trips(q{sub f { $_ = 9; my @a; push @a, 1, 2; my @c = (3); my $s = ""; for (@a) { for (@c) { $s .= $_ } $s .= $_ } print "$s|$_\n" } f();},
    'a bare array under $_: a nested foreach');
round_trips(q{sub f { $_ = 9; my @a; push @a, 1, 2; my @c = (3); my $s = ""; for my $x (@a) { my @b = map { $_ * 2 } @c; $s .= "$x@b" } print "$s|$_\n" } f();},
    'a bare array: a nested map');
round_trips(q{sub f { $_ = 9; my @a; push @a, 1, 2; my $s = ""; for (@a) { $s .= "$_" } print "$s|$_\n" } f();},
    'a bare array under $_ after a store to $_');

# A SHIFT, POP, UNSHIFT OR SPLICE OF THE LIST moves the elements under the
# index; one of another array cannot, over a list nothing else reaches.
round_trips(q{sub f { my @a; $a[1] = 5; my $s=""; for my $x (@a) { shift @a; $s .= defined $x ? $x : "u" } print "$s|", scalar(@a), "\n" } f();},
    'a bare array with a hole: a shift');
round_trips(q{sub f { my @a; push @a, 1, 2, 3; my $s=""; for my $x (@a) { pop @a; $s .= $x } print "$s|@a\n" } f();},
    'a bare array: a pop');
round_trips(q{sub f { my @a; push @a, 1, 2, 3; my $s=""; for my $x (@a) { splice @a, 1, 1; $s .= $x } print "$s|@a\n" } f();},
    'a bare array: a splice');
round_trips(q{sub f { my @a; push @a, 1, 2; my $s=""; for my $x (@a) { unshift @a, 0 if @a < 4; $s .= $x } print "$s|@a\n" } f();},
    'a bare array: an unshift');
round_trips(q{sub f { my @a; push @a, 1, 2; my @q = (7, 8); my $s=""; for my $x (@a) { $s .= $x . shift @q } print "$s|@a\n" } f();},
    'a bare array: a shift of another array');

# AN ITERATOR WRITE GOES BACK TO THE INDEX, which a later element store
# overwrites in perl and not here (`55|5 5` for `57|5 7`).
refuses(q{sub f { my @a; push @a, 1, 2; my $s=""; for my $x (@a) { $x = 5; $a[1] = 7; $s .= $x } print "$s|@a\n" } f();},
    $UNPROVEN, 'a bare array: an alias write, then an element store');
refuses(q{sub f { my @a; push @a, 1, 2; my $s=""; for my $x (@a) { my $g = sub { $x }; $a[0] = 5; $s .= $g->() } print "$s|@a\n" } f();},
    $UNPROVEN, 'a bare array: a closure over the alias and an element store');
refuses(q{sub f { my @a; push @a, 1, 2; my $s=""; for my $x (@a) { my $g = sub { $x }; shift @a; $s .= $g->() } print "$s|@a\n" } f();},
    qr/$UNPROVEN|an anonymous sub closing over \$x|a foreach whose body reshapes the array it iterates/, 'a bare array: a closure over the alias and a shift');
refuses(q{sub f { my @a; push @a, 1, 2; my $s=""; for my $x (@a) { $x = 5; @a[1] = (7); $s .= $x } print "$s|@a\n" } f();},
    $UNPROVEN, 'a bare array: an alias write, then a slice store');
refuses(q{sub f { my @a; push @a, 1, 2; my $s=""; for my $x (@a) { $x = 5; $s .= "@a" } print "$s|@a\n" } f();},
    $UNPROVEN, 'a bare array: an alias write, then a whole-array read');

# A REFERENCE TO THE ITERATOR OR A CLOSURE OVER IT outlives the pass: a write
# through it after the loop reaches perl's element (`1 2` for `9 2`), and a
# closure saw the last pass (`2,2` for `1,2`).
refuses(q{sub f { my @a; push @a, 1, 2; my @r; for my $x (@a) { push @r, \$x } ${$r[0]} = 9; print "@a\n" } f();},
    qr/$UNPROVEN|a reference to a foreach iterator is not yet lowered/, 'a bare array: a reference to the iterator, written after the loop');
refuses(q{sub f { my @a; push @a, 1, 2; my %h; for my $x (@a) { $h{$x} = \$x } ${$h{1}} = 9; print "@a\n" } f();},
    qr/$UNPROVEN|a reference to a foreach iterator is not yet lowered/, 'a bare array: a reference to the iterator stored in a hash');
refuses(q{sub f { my @a; push @a, 1, 2; my @s; for my $x (@a) { push @s, sub { $x } } print join(",", map { $_->() } @s), "\n" } f();},
    $UNPROVEN, 'a bare array: a closure over the iterator');

# A CALL may write `$_`, the array, or its elements. `$_` is aliased to the
# element each pass (t/deparse-a-callee-reads-the-topic-by-name.t), so a
# callee's write to it lands there.
round_trips(q{sub g { $_ = 100 } sub f { my @a; push @a, 1, 2; for (@a) { g() } print "|@a\n" } f();},
    'a bare array under $_: a callee writing $_');
round_trips(q{my @F = (1, 2); sub g { $F[0] = 9 } sub f { my $s = ""; for my $x (@F) { g(); $s .= $x } print "$s|@F\n" } f();},
    'a captured file array: a callee storing an element');
round_trips(q{sub f { my @a; push @a, 1, 2; my $s = ""; my $g = sub { $a[1] = 9 }; for my $x (@a) { $g->(); $s .= $x } print "$s|@a\n" } f();},
    'a bare array: a closure call storing an element');
# The topic is aliased each pass, and the body reads it before no call:
# the callee's write lands in the element.
round_trips(q{use v5.42; sub g { $_ = 100 } sub f($r) { for (@$r) { g() } "@$r" } print f([1,2]), "\n";},
    'a topic deref: a callee writing $_');

# WHAT STILL LOWERS: the list reached through the iterator alone.
round_trips(q{sub f { my @a; push @a, 1, 2; my $s=""; for my $x (@a) { $s .= $x } print "$s|@a\n" } f();},
    'a bare array: the iterator read');
round_trips(q{sub f { my @a; push @a, 3, 4; for (@a) { $_ *= 2 } print "@a\n" } f();},
    'a bare array under $_: the iterator written');
round_trips(q{use v5.42; sub f($k) { my %s; $s{$_} = 1 for $k->@*; join ",", sort keys %s } print f([qw(b a)]), "\n";},
    'a topic deref: a hash store keyed by the iterator');
round_trips(q{sub f { my @a; push @a, 1, 2; my @o; for my $x (@a) { push @o, $x * 2 } print "@o|@a\n" } f();},
    'a bare array: a push onto another array');
round_trips(q{our $p = 5; sub f { my @a; push @a, 1, 2; my $s = ""; for $p (@a) { $s .= $p } "$s|$p" } print f(), "\n";},
    'a bare array: a package iterator read');

done_testing;
