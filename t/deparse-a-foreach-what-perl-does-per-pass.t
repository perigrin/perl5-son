# ABOUTME: A foreach whose body reshapes its own list, nests in a loop that grows it, writes a
# ABOUTME: package iterator, or binds several iterators: each round trips or refuses by name.

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

# PERL'S ITERATOR IS THE ELEMENT, AND THIS LOWERING'S AN INDEX READ. They agree
# only while nothing else moves or writes the list. A shift, splice or in-place
# sort in the body -- direct, through a reference, or in a callee -- moves the
# elements under the index (`2|2` for perl's `1|2`). Over a typed array a
# reshape by name refuses; over an unproven list (a bare-declared array, or a
# deref under `$_` or a package iterator) every body that may reach the list
# other than through the iterator refuses. A push moves nothing, and lowers.
my $RESHAPE  = qr/GAP: a foreach whose body reshapes the array it iterates/;
my $UNPROVEN = qr/GAP: a foreach over an unproven list .* whose body may reach the list other than through its iterator/;
my $STALE    = qr/GAP: an element read in a loop is spelled after a store/;
refuses(q{sub f { my @a; push @a, 1, 2; my $s=""; for my $x (@a) { $s .= $x; shift @a } print "$s|@a\n" } f();},
    $UNPROVEN, 'a shift of a bare-declared array in its own loop');
refuses(q{sub f { my @a = (1, 2); my $s=""; for my $x (@a) { $s .= $x; shift @a } print "$s|@a\n" } f();},
    $RESHAPE, 'a shift of an assigned array in its own loop');
refuses(q{use v5.42; sub f($r) { my $s=""; for (@$r) { $s .= $_; shift @$r } "$s|@$r" } print f([1,2]), "\n";},
    $UNPROVEN, 'a shift of a dereferenced array in its own loop');
round_trips(q{sub f { my @a = (1, 2); my $s=""; for my $x (@a) { $s .= $x; push @a, 3 if $x == 1 } print "$s|@a\n" } f();},
    'a push onto the array in its own loop');
refuses(q{sub f { my @a = (1, 2, 3); my $s=""; for my $x (@a) { $s .= $x; splice @a, 1, 1 } print "$s|@a\n" } f();},
    $RESHAPE, 'a splice of the array in its own loop');
refuses(q{use v5.42; sub f($h) { my $s = ""; for ($h->{q}->@*) { $s .= $_; push $h->{q}->@*, 3 if $_ == 1 } $s } print f({q => [1,2]}), "\n";},
    $UNPROVEN, 'a push onto the same field deref inside its loop');
refuses(q{sub f { my @a; push @a, 1, 2; my $r = \@a; my $s=""; for my $x (@a) { $s .= $x; shift @$r } print "$s|@a\n" } f();},
    $UNPROVEN, 'a shift through a reference to the iterated array');
refuses(q{sub f { my @a; push @a, 1, 2; my $s=""; my $g = sub { shift @a }; for my $x (@a) { $s .= $x; $g->() } print "$s|@a\n" } f();},
    $UNPROVEN, 'a shift in a closure called from the body');
refuses(q{my @F = (1, 2); sub g { shift @F } sub f { my $s=""; for my $x (@F) { $s .= $x; g() } print "$s|@F\n" } f();},
    $UNPROVEN, 'a shift in a named sub over a captured file lexical');
refuses(q{my @F = (1, 2, 3); sub g { pop @F } sub f { my $s=""; for my $x (@F) { $s .= $x; g() } print "$s|@F\n" } f();},
    $UNPROVEN, 'a pop in a named sub over a captured file lexical');
refuses(q{use v5.42; sub f($r, $q) { my $s=""; for (@$r) { $s .= $_; shift @$q } "$s|@$r" } my $x = [1,2]; print f($x, $x), "\n";},
    $UNPROVEN, 'a shift through a second reference to the same array');
refuses(q{use v5.42; sub f($r) { my $s = ""; my $q = $r->{a}; for (@{$r->{a}}) { $s .= $_; shift @$q } $s } print f({a=>[1,2]}), "\n";},
    $UNPROVEN, 'a shift through a copied reference to the iterated deref');
refuses(q{use v5.42; sub f($r) { my $s=""; for my $x (@$r) { $s .= $x; @$r = sort { $b <=> $a } @$r } "$s|@$r" } print f([1,3,2]), "\n";},
    $RESHAPE, 'a sort assigned back through the reference');
round_trips(q{sub f { my @a = (1, 2, 3); my $s=""; for my $x (@a) { $s .= $x; push @a, 9 if $x == 1 } print "$s|@a\n" } f();},
    'a push that adds a pass');

# A BODY THAT REASSIGNS THE ARRAY'S OWN SLOT carries the new array on a loop
# Phi, and the loop indexed the binding it was entered with -- `@a = sort @a`,
# which perl does in place, gave `312` for `323`.
my $REASSIGN = qr/GAP: a foreach whose body reassigns the array it iterates/;
refuses(q{sub f { my @a; push @a, 3, 1, 2; my $s=""; for my $x (@a) { $s .= $x; @a = sort @a } print "$s|@a\n" } f();},
    $UNPROVEN, 'an in-place sort of the iterated array');
refuses(q{sub f { my @a; push @a, 1, 2; my $s=""; for my $x (@a) { $s .= $x; @a = () if $x == 1 } print "$s|@a\n" } f();},
    $UNPROVEN, 'a clear of the array in its own loop');
refuses(q{sub f { my @a = (1, 2, 3); my $s=""; for my $x (@a) { $s .= $x; undef @a } print "$s|@a\n" } f();},
    $RESHAPE, 'an undef of the array in its own loop');
refuses(q{sub f { my @a = (1, 2, 3); my $s=""; for my $x (@a) { $s .= $x; @a = reverse @a } print "$s|@a\n" } f();},
    $REASSIGN, 'an in-place reverse of the iterated array');

# A STORE TO THE ELEMENT, whoever makes it -- the body, an inner loop's alias, a
# reference, a callee -- is seen by perl's alias. The index read is spelled
# where it is used, which sees a store made before that point; the renderer
# refuses a read whose value is carried past a later store to its aggregate.
refuses(q{sub f { my @a; push @a, 1, 2; my $s=""; for my $x (@a) { $s .= $x; $_ = 0 for @a } print "$s|@a\n" } f();},
    $UNPROVEN, 'an inner loop zeroing the elements after the read');
refuses(q{sub f { my @a; push @a, 1, 2; my $s=""; for my $x (@a) { $s .= $x; s/1/5/ for @a } print "$s|@a\n" } f();},
    $UNPROVEN, 'an inner s/// through its alias after the read');
round_trips(q{sub f { my @a = (3,4); for my $x (@a) { print $x; $a[1] = 1; } print "|@a\n" } f();},
    'an element store after a printed read');
refuses_render(q{sub f { my @a = (1,2); my $s=""; for my $x (@a) { $s .= $x; $a[0] = 7; } print "$s|@a\n" } f();},
    $STALE, 'an element store after a carried read');
refuses_render(q{sub f { my @a = (1,2); my $s=""; for my $x (@a) { $a[0] = 7; $s .= $x; } print "$s|@a\n" } f();},
    $STALE, 'an element store before the read');
round_trips(q{sub f { my @a = (1,2); my $s=""; for my $x (@a) { for my $y (@a) { $y .= "z" } $s .= $x; } print "$s|@a\n" } f();},
    'an inner loop writing the elements before the read');
round_trips(q{sub f { my @a = (1,2); for my $x (@a) { for my $y (@a) { $y .= "z" } print $x; } print "|@a\n" } f();},
    'an inner loop writing the elements before a print of the iterator');
round_trips(q{sub f { my @a = (1,2); my $s=""; for my $x (@a) { s/1/5/ for @a; $s .= $x; } print "$s|@a\n" } f();},
    'an inner s/// before the read');
round_trips(q{sub f { my @a = (1,2); my $r = \@a; my $s=""; for my $x (@a) { $r->[0] = 9; $s .= $x } print "$s|@a\n" } f();},
    'a store through a reference before the read');
refuses(q{my @F=(1,2); sub g { $F[0] = 9 } sub f { for my $x (@F) { g(); print $x } print "|@F\n" } f();},
    $UNPROVEN, 'a callee storing into the element before the read');
refuses_render(q{sub g { $_[0] = 9 } sub f { my @a = (1,2); for my $x (@a) { g($a[0]); print $x } print "|@a\n" } f();},
    $STALE, 'a callee writing the element through @_ before the read');
refuses(q{sub f { my @a = (1,2,3); my $s=""; for my $x (@a) { $s .= $x; shift @a; $s .= $x; } print "$s|@a\n" } f();},
    $RESHAPE, 'a read on both sides of a shift');
refuses(q{my @F=(1,2,3); sub g { shift @F } sub f { my $s=""; for my $x (@F) { g(); $s .= $x } print "$s|@F\n" } f();},
    $UNPROVEN, 'a read after a callee shifts');
round_trips(q{sub f { my @a = ([1],[2]); my $s = ""; for my $x (@a) { push @$x, 5; $s .= scalar(@$x) . $x->[0] } print "$s\n" } f();},
    'a push through the element itself');
# A READ BETWEEN TWO STORES whose value only reaches the back edge has lost its
# place in the pass: spelled there, it read the second store.
refuses_render(q{sub f { my @a = (1,2); my $s=""; for my $x (@a) { $a[0] = 7; $s .= $x; $a[0] = 8 } print "$s|@a\n" } f();},
    $STALE, 'a carried read between two element stores');
# A STORE THROUGH A REFERENCE is not one the renderer matches to the read's
# aggregate, so the read is spelled at the back edge after the second store:
# `82` for perl's `72`, as on the base this branched from.
{
    my $todo = todo q{a carried read past a store through a reference is not refused};
    refuses_render(q{sub f { my @a = (1,2); my $r = \@a; my $s=""; for my $x (@a) { $r->[0] = 7; $s .= $x; $r->[0] = 8 } print "$s|@a\n" } f();},
        $STALE, 'a carried read between two stores through a reference');
}
# NOT EVERY LATER STORE COUNTS: a read inside an inner loop that stores it, and
# a read pushed twice -- chalk's CoreItemIndex::build_from_grammar and
# Serialize::JSON::_all_nodes_topo.
round_trips(q{my @o; my $n = 0; sub reg { $n++ } sub f { my @r = ("a","b"); for my $r (@r) { for my $d (0..1) { my $id = reg(); $o[$id] = $r } } print "@o\n" } f();},
    'an alias read after a call, inside an inner loop that stores it');
round_trips(q{sub f { my @a = (1,2,1,3); my (%seen, @x, @y); for my $c (@a) { next if $seen{$c}++; push @x, $c; push @y, $c } print "@x|@y\n" } f();},
    'an alias read after a store, pushed twice');
refuses_render(q{sub g { $_[0] = 9 } sub f { my @a = (1,2); my $s = ""; for my $x (@a) { $a[0] = 5; $s .= $x; g($a[0]) } print "$s|@a\n" } f();},
    $STALE, 'a carried alias read before a callee writes the element');
round_trips(q{sub f { my @a = (1,2); my @b = (5,6); my $s=""; for my $x (@a) { for my $y (@b) { $y .= "z" } $s .= $x; } print "$s|@b\n" } f();},
    'an inner loop writing another array');
round_trips(q{sub f { my @a = (1,2); my $s=""; for my $x (@a) { for my $k (1..2) { $a[0] = 7 } $s .= $x; } print "$s|@a\n" } f();},
    'an element store in an inner range loop before the read');
refuses_render(q{sub f { my @a = (3,4); my $s = 0; for (@a) { $_ *= 2; $s += $_ } print "$s|@a\n" } f();},
    $STALE, 'the alias written, then read');
round_trips(q{sub f { my @a = (1,2); for (@a) { $_ = 0 } print "@a\n" } f();},
    'the alias written and never read');

# THE WRITE-BACK GOES TO THE INDEX and perl's alias to the element, so a body
# that writes its alias and may move the elements refuses.
my $WRITE_RESHAPE = qr/GAP: a foreach whose body writes its alias and may reshape the array/;
refuses(q{sub f { my @a = (1, 2, 3); for my $x (@a) { $x .= "y"; shift @a } print "@a\n" } f();},
    $WRITE_RESHAPE, 'an alias write then a shift');
refuses(q{sub f { my @a = (1, 2, 3); for my $x (@a) { shift @a; $x .= "y" } print "@a\n" } f();},
    $WRITE_RESHAPE, 'a shift then an alias write');
refuses(q{sub f { my @a = (1, 2, 3); my $r = \@a; for my $x (@a) { $x .= "y"; shift @$r } print "@a\n" } f();},
    $WRITE_RESHAPE, 'an alias write then a shift through a reference');
refuses(q{sub f { my @a = (1, 2, 3); my $g = sub { shift @a }; for my $x (@a) { $x .= "y"; $g->() } print "@a\n" } f();},
    $WRITE_RESHAPE, 'an alias write then a closure call');
refuses(q{sub f { my @a = (1, 2, 3); for my $x (@a) { $x .= "y"; unshift @a, 0 if @a < 4 } print "@a\n" } f();},
    $WRITE_RESHAPE, 'an alias write then an unshift');
round_trips(q{sub f { my @a = (1, 2, 3); for my $x (@a) { $x .= "y" } print "@a\n" } f();},
    'an alias write alone');

# A NESTED LOOP OVER AN ARRAY was invisible to the outer loop's scout: the scout
# binds every slot to a placeholder, the placeholder is no array, and the inner
# foreach refused there -- so the outer loop built no Phi for what the inner
# body writes and the accumulator restarted every pass (`11` for `111`).
round_trips(q{sub f { my @a; push @a, 1; my $s=""; for my $k (1..2) { for my $x (@a) { $s.=$x } push @a, $k } print "$s\n" } f();},
    'an inner loop over a bare array the outer loop pushes');
round_trips(q{sub f { my @a = (1); my $s=""; for my $k (1..2) { for my $x (@a) { $s.=$x } } print "$s\n" } f();},
    'an accumulator written by an inner array loop');
round_trips(q{sub f { my @a = (1); my $s=""; my $k=0; while ($k++ < 2) { for my $x (@a) { $s.=$x } } print "$s\n" } f();},
    'an inner array loop in a while');
round_trips(q{sub f { my @a = (1); my $s=""; for my $k (1..2) { for my $x (@a) { $s.=$x } $s .= "-" } print "$s\n" } f();},
    'an inner array loop then a write in the outer body');
round_trips(q{sub f { my @a = (1,2); my $s=""; for my $k (@a) { for my $x (@a) { $s.="$k$x" } } print "$s\n" } f();},
    'an array loop inside an array loop');

# THE SAME MISS WITHOUT AN INNER LOOP: a C-style `for` with nested `next`
# guards ahead of it kept its scout from reaching the increment of the second
# loop, which then emitted `$i = $i` and never terminated (chalk's
# StructPromotion::_rewrite_method_body). The real walk sees the write.
refuses(q{sub f { my ($b) = @_; my %r; for (my $i = 0; $i < scalar(@$b); $i++) { my $s = $b->[$i]; next unless defined $s; if ($s > 1) { next unless $s > 2; $r{$i} = 1 } } for (my $i = 0; $i < @$b; $i++) { next if $r{$i}; print $i } print "\n" } f([1,2,3,undef,5]);},
    qr/GAP: a loop body writes a variable its scout missed/, 'a C-style loop whose scout misses its increment');

# PERL LOCALIZES A PACKAGE ITERATOR: whatever the body writes, the variable
# holds its pre-loop value again after the loop.
round_trips(q{use v5.42; our $p = 0; sub f($r) { my $s=""; for $p (@$r) { $p *= 2 } "@$r|$p" } print f([1,2]), "\n";},
    'a package iterator written over a deref is restored');
round_trips(q{our $p = 0; sub f { my @a = (1,2); for $p (@a) { $p .= "x" } "@a|$p" } print f(), "\n";},
    'a package iterator written over an array is restored');
round_trips(q{our $p = 0; sub f { my $s = ""; for $p (1..2) { $p .= "x"; $s .= $p } "$s|$p" } print f(), "\n";},
    'a package iterator written over a range is restored');
round_trips(q{$_ = "z"; sub f { my @a = (1,2); for (@a) { $_ .= "x" } "@a|$_" } print f(), "\n";},
    'an implicit $_ written in the body is restored');
round_trips(q{our $p = 5; sub f { my @a = (1,2); my $s=""; for $p (@a) { $s .= $p } "$s|$p" } print f(), "\n";},
    'a package iterator only read keeps its value');
# THE RESTORE VALUE IS THE ONE AT LOOP ENTRY. Inside an outer loop that
# carries the variable, the second pass restored the value from before the
# outer loop (`77` for perl's `71`).
round_trips(q{our $p = 7; sub f { my @a; push @a, 1, 2; my $s = ""; for my $k (1..2) { for $p (@a) { $p++ } $s .= $p; $p = $k } print "$s|$p|@a\n" } f();},
    'a package iterator restored inside an outer loop that writes it');
round_trips(q{our $p = 7; sub f { my @a = (1, 2); my $s = ""; my $k = 0; while ($k++ < 2) { for $p (@a) { $p .= "x" } $s .= $p; $p = $k } print "$s|$p|@a\n" } f();},
    'a package iterator restored inside a while that writes it');
round_trips(q{our $p = 7; sub f { my $s = ""; for my $k (1..2) { for $p (1..2) { $p++ } $s .= $p; $p = $k } print "$s|$p\n" } f();},
    'a package range iterator restored inside an outer loop');
# A NESTED LOOP OVER THE SAME NAME restores the outer element into it, which
# the outer loop's exit must undo.
round_trips(q{our $p = 7; sub f { my @a = (1, 2); my @b = (5); my $s = ""; for $p (@a) { for $p (@b) { $p++ } $s .= $p; } print "$s|$p|@a|@b\n" } f();},
    'a package iterator nested in a loop over the same name');
round_trips(q{our $p = 7; sub f { my $s = ""; for $p (1..2) { for $p (5..5) { $p++ } $s .= $p; } print "$s|$p\n" } f();},
    'a package range iterator nested in a range over the same name');
round_trips(q{$_ = "q"; sub f { my @a = (1, 2); my @b = (5); my $s = ""; for (@a) { for (@b) { $_++ } $s .= $_; } print "$s|$_|@a|@b\n" } f();},
    'an implicit $_ nested in a loop over $_');
round_trips(q{$_ = "q"; sub f { my $s = ""; for (1..2) { for (5..6) { $s .= $_ } $s .= $_; } print "$s|$_\n" } f();},
    'an implicit $_ range nested in a range over $_');

# THE ALIAS IS NOT THE VARIABLE in this lowering: a callee reads and writes the
# package variable, and a die unwinds past the restore at the loop's exit.
my $CALLEE = qr/GAP: a foreach over a package variable whose body calls a sub/;
refuses(q{our $p = 7; sub g { $p = 100 } sub f { my @a; push @a, 1, 2; for $p (@a) { g() } print "$p|@a\n" } f();},
    $UNPROVEN, 'a callee writing the package iterator');
refuses(q{our $p = 7; sub g { print $p } sub f { my @a = (1,2); for $p (@a) { g() } print "$p\n" } f();},
    $CALLEE, 'a callee reading the package iterator');
refuses(q{our $p = 7; sub g { $p = 100 } sub f { for $p (1..2) { g() } print "$p\n" } f();},
    $CALLEE, 'a callee writing a package range iterator');
# THE IMPLICIT `$_` IS SPARED THE CALL REFUSAL (`f($_) for @x` is everywhere),
# so a callee that writes the caller's topic unpassed is a known miscompile.
{
    my $todo = todo q{a callee writing the caller's $_ is not modelled};
    round_trips(q{sub g { $_ = 100 } sub f { my @a = (1, 2); for (@a) { g() } print "|@a\n" } f();},
        'a callee writing the implicit $_');
}
round_trips(q{sub g { "<$_[0]>" } sub f { my @a = (1, 2); my $s = ""; for (@a) { $s .= g($_) } print "$s\n" } f();},
    'the implicit $_ passed to a callee');
my $UNWIND = qr/GAP: a foreach over a package variable whose body writes it and can die/;
refuses(q{our $p = 7; sub f { my @a; push @a, 1, 2; eval { for $p (@a) { $p++; die "x\n" if $p == 2 } }; print "$p|@a|$@" } f();},
    $UNWIND, 'a die past the restore of a package iterator');
refuses(q{our $p = 7; sub f { eval { for $p (1..2) { $p++; die "x\n" if $p == 2 } }; print "$p|$@" } f();},
    $UNWIND, 'a die past the restore of a package range iterator');
refuses(q{sub f { my @a = (1, 2); eval { for (@a) { $_ .= "x"; die "x\n" } }; print "@a|$@" } f();},
    $UNWIND, 'a die past the restore of the implicit $_');

# SEVERAL ITERATORS take several elements per pass; the single-iterator
# lowering bound only the first and left the rest undef.
my $MULTI = qr/GAP: a foreach with several iterator variables/;
refuses(q{sub f { my @a; push @a, 1, 2; my $s=""; for my ($k, $v) (@a) { $s .= "$k$v" } $s } print f(), "\n";},
    $MULTI, 'two iterators over a bare array');
refuses(q{sub f { my @a = (1,2); my $s=""; for my ($k, $v) (@a) { $s .= "$k$v" } $s } print f(), "\n";},
    $MULTI, 'two iterators over an assigned array');
refuses(q{use v5.42; sub f($r) { my $s=""; for my ($k, $v) (@$r) { $s .= "$k$v" } $s } print f([1,2]), "\n";},
    $MULTI, 'two iterators over a deref');
refuses(q{sub f { my $s=""; for my ($k, $v) (1..4) { $s .= "$k$v" } $s } print f(), "\n";},
    $MULTI, 'two iterators over a range');
refuses(q{sub f { my $s=""; for my ($k, $v, $w) (1,2,3) { $s .= "$k$v$w" } $s } print f(), "\n";},
    $MULTI, 'three iterators over a list');

done_testing;
