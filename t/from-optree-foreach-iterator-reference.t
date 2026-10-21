# ABOUTME: A reference to a foreach iterator is refused by name: the lowering binds a
# ABOUTME: copy and writes it back each pass, and a reference can outlive the pass.

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

sub produce ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f;
    open my $eh, '<', "$dir/err" or die $!;
    my $err = do { local $/; <$eh> } =~ s/^\S+ syntax OK\n//mr;
    return (eval { JSON::PP->new->decode($j) }, $err);
}

my $GAP = qr/GAP: a reference to a foreach iterator is not yet lowered/;

sub refused ($src, $name) {
    my (undef, $err) = produce($src);
    like $err, $GAP, "$name: refused by name";
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my ($data, $err) = produce($src);
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) { fail "$name: renders"; diag $d->gap; return }
    is run_perl($out), $want, $name or diag $out;
}

# perl prints 5: the reference is the caller's element.
refused(<<'SRC', 'a reference carried out of the loop');
sub f { my $n = 0; for my $x (@_) { $n = \$x } $$n = 5; return $n }
my @a = (1); f(@a); print "$a[0]\n";
SRC

refused(<<'SRC', 'the same, from a reference init');
sub f { my $z; my $n = \$z; for my $x (@_) { $n = \$x } $$n = 5; return $n }
my @a = (1); f(@a); print "$a[0]\n";
SRC

refused(<<'SRC', 'a reference kept on a guard');
my @a = (1,2,3); my $r; for my $x (@a) { $r = \$x if $x == 2 } $$r = 9; print "@a\n";
SRC

refused(<<'SRC', 'a reference pushed onto an outer array');
my @a = (1,2,3); my @r; for my $x (@a) { push @r, \$x } ${$r[1]} = 9; print "@a\n";
SRC

refused(<<'SRC', 'a reference stored into a hash');
my @a = (1,2,3); my %h; for my $x (@a) { $h{$x} = \$x } ${$h{3}} = 9; print "@a\n";
SRC

refused(<<'SRC', 'a reference handed to a sub that keeps it');
sub keep { our $K = $_[0] } my @a = (1,2); for my $x (@a) { keep(\$x) } $$K = 7; print "@a\n";
SRC

# A range iterator aliases nothing the program can see again.
round_trips(<<'SRC', 'references to a range iterator');
my @r; for my $i (1..3) { push @r, \$i } print join(",", map { $$_ } @r), "\n";
SRC

# Passing the iterator itself, not a reference, keeps its write-back.
round_trips(<<'SRC', 'an iterator passed to a sub that writes it');
sub bump { $_[0]++ } my @a = (1,2); for my $x (@a) { bump($x) } print "@a\n";
SRC

# A REFERENCE INTO THE ITERATOR is one to the element too: perl prints `1 5`.
refused(<<'SRC', 'an lvalue substr of the iterator, carried out');
my @a = (1,2); my $r; for my $x (@a) { $r = \substr($x, 0, 1) } $$r = 5; print "@a\n";
SRC

refused(<<'SRC', 'an lvalue vec of the iterator, carried out');
my @a = (1,2); my $r; for my $x (@a) { $r = \vec($x, 0, 8) } $$r = 65; print "@a\n";
SRC

refused(<<'SRC', 'a reference list of the iterator, carried out');
my @a = (1,2); my $r; for my $x (@a) { ($r) = \($x) } $$r = 5; print "@a\n";
SRC

refused(<<'SRC', 'a reference in an anonymous array, carried out');
my @a = (1,2); my $r; for my $x (@a) { $r = [\$x] } ${$r->[0]} = 5; print "@a\n";
SRC

# A PACKAGE ITERATOR is the element too, and a reference to it names the glob's
# scalar, which the lowering never writes: perl prints `9 9` and `1 5`.
my $PKG = qr/GAP: a reference to a package foreach iterator is not yet lowered/;
for ( [ 'within the pass',
        'our @A = (1,2); our $x; for $x (@A) { my $r = \$x; $$r = 9 } print "@A\n";' ],
      [ 'an `our` iterator, carried out',
        'our @A = (1,2); my $r; for our $x (@A) { $r = \$x } $$r = 5; print "@A\n";' ],
      [ 'a qualified iterator, carried out',
        'our @A = (1,2); my $r; for $main::x (@A) { $r = \$main::x } $$r = 5; print "@A\n";' ],
      [ '$_, carried out',
        'my @a = (1,2); my $r; for (@a) { $r = \$_ } $$r = 5; print "@a\n";' ] ) {
    my (undef, $err) = produce("$_->[1]\n");
    like $err, $PKG, "a package iterator referenced $_->[0]: refused by name";
}

# A CALL'S VALUE CAN BE A REFERENCE TO ITS ARGUMENT: `k` returns `\$_[0]`, which
# is the element. perl prints `1 5` (`5 2` for the push and the hash).
my $CALL = qr/GAP: a call's value that may alias a foreach iterator is not yet lowered/;
for ( [ 'carried out', 'my $r; for my $x (@a) { $r = k($x) } $$r = 5;' ],
      [ 'list-assigned out', 'my $r; for my $x (@a) { ($r) = k($x) } $$r = 5;' ],
      [ 'pushed', 'my @r; for my $x (@a) { push @r, k($x) } ${$r[0]} = 5;' ],
      [ 'stored into a hash', 'my %h; for my $x (@a) { $h{$x} = k($x) } ${$h{1}} = 5;' ],
      [ 'through a body lexical', 'my $r; for my $x (@a) { my $v = k($x); $r = $v } $$r = 5;' ],
      [ 'through a body array', 'my $r; for my $x (@a) { my @v = k($x); $r = $v[0] } $$r = 5;' ],
      [ 'behind ||', 'my $r; for my $x (@a) { $r = k($x) || 0 } $$r = 5;' ] ) {
    round_trips(
        "sub k { return \\\$_[0] } sub f { my \@a = (1,2); $_->[1] return \"\@a\" } print f(), \"\\n\";\n",
        "a call's value $_->[0]");
}

# A REFERENCE USED ONLY WITHIN THE PASS writes the copy, and the write-back
# carries it to the element.
round_trips(<<'SRC', 'a reference held in a body lexical');
my @a = (1,2); for my $x (@a) { my $r = \$x; $$r = 9 } print "@a\n";
SRC

round_trips(<<'SRC', 'a reference held in a body lexical, read and written');
my @a = (1,2); for my $x (@a) { my $r = \$x; $$r = $$r * 10 } print "@a\n";
SRC

# A call whose value is only tested, or thrown away, hands back nothing.
round_trips(<<'SRC', 'a call on the iterator in a condition');
sub big { $_[0]++; $_[0] > 2 } my @a = (1,2); my $n = 0; for my $x (@a) { $n++ if big($x) } print "@a $n\n";
SRC

round_trips(<<'SRC', 'a call on the iterator under unless');
sub big { $_[0] *= 3; $_[0] > 3 } my @a = (1,2); my @o; for my $x (@a) { next unless big($x); push @o, $x } print "@a @o\n";
SRC


# A NAMED SUB THAT STORES `\$_[0]` keeps the element too, its value thrown
# away: perl prints `5 2`.
round_trips(<<'SRC', 'a named sub that keeps a reference to its argument');
our @K; sub keep { push @K, \$_[0] } my @a = (1,2); for my $x (@a) { keep($x) } ${$K[0]} = 5; print "@a\n";
SRC

round_trips(<<'SRC', 'a named sub that hands its argument on');
our @K; sub keep { push @K, \$_[0] } sub pass { keep($_[0]) } my @a = (1,2); for my $x (@a) { pass($x) } ${$K[0]} = 5; print "@a\n";
SRC

# A named sub that takes no reference and hands no argument on keeps nothing.
round_trips(<<'SRC', "a named helper's value pushed");
sub twice { $_[0] * 2 } my @a = (1,2); my @r; for my $x (@a) { push @r, twice($x) } print "@a @r\n";
SRC

round_trips(<<'SRC', 'a call value held in a body lexical and read');
sub twice { $_[0] * 2 } my @a = (1,2); my $o = ""; for my $x (@a) { my $v = twice($x); $o .= $v } print "@a $o\n";
SRC

round_trips(<<'SRC', 'a call value held in a body array and joined');
sub two { ($_[0], $_[0]) } my @a = (1,2); my $o = ""; for my $x (@a) { my @v = two($x); $o .= "@v;" } print "@a $o\n";
SRC

# A CLOSURE HELD IN A LEXICAL BOUND ONCE is a callee whose body can be read,
# as a named sub's is: chalk's FilterComposite calls `$slot_verdict->($sr,
# ...)` on its iterator and keeps the verdict. A signature copies its
# arguments, so the body holds no alias.
round_trips(<<'SRC', "a closure's value kept, the closure bound once");
use v5.42; my @a = (1,2); my $g = sub ($x, $y) { $x + $y }; my @r; for my $i (@a) { my $v = $g->($i, 1); push @r, $v } print "@a @r\n";
SRC
# ONE THAT KEEPS A REFERENCE to its argument still refuses; so does a
# lexical bound twice, whose callee the scan cannot name.
round_trips(<<'SRC', 'a closure that returns a reference to its argument');
my @a = (1,2); my $k = sub { \$_[0] }; my $r; for my $x (@a) { $r = $k->($x) } $$r = 5; print "@a\n";
SRC
round_trips(<<'SRC', 'a lexical bound to two closures');
my @a = (1,2); my $k = sub { $_[0] }; $k = sub { \$_[0] } if @ARGV == 0; my $r; for my $x (@a) { $r = $k->($x) } $$r = 5; print "@a\n";
SRC

# A FOREACH OVER @_ ALIASES THE CALLER'S ARGUMENTS, and the caller's graph
# does not see a write-back into @_. Every write form is refused by name.
my $ARGS = qr/GAP: a write to a foreach iterator over \@_/;
for my $case (
    [ 'a write through a reference to the iterator, then a read',   # perl 4 2 4
      'sub f { my $v = 0; for my $x (@_) { my $r = \$x; $$r = $x * 2; $v = $x } return $v } my @a=(1,2); print f(@a), " @a\n";' ],
    [ 'a constant written through a reference',                     # perl 7 7 7
      'sub f { my $v = 0; for my $x (@_) { my $r = \$x; $$r = 7; $v = $x } return $v } my @a=(1,2); print f(@a), " @a\n";' ],
    [ 'the iterator assigned',
      'sub f { for my $x (@_) { $x = $x * 2 } return 1 } my @a=(1,2); print f(@a), " @a\n";' ],
    [ 'an implicit $_ assigned',
      'sub f { for (@_) { $_ = $_ + 1 } return 1 } my @a=(1,2); print f(@a), " @a\n";' ],
    [ 'the iterator incremented',
      'sub f { for my $x (@_) { $x++ } return 1 } my @a=(1,2); print f(@a), " @a\n";' ],
    [ 'the iterator written by a callee',
      'sub g { $_[0]++ } sub f { for my $x (@_) { g($x) } return 1 } my @a=(1,2); print f(@a), " @a\n";' ],
    [ 'an implicit $_ substituted',
      'sub f { for (@_) { s/1/9/ } return 1 } my @a=(1,2); print f(@a), " @a\n";' ],
    [ 'an implicit $_ written by a callee',
      'sub g { $_[0]++ } sub f { for (@_) { g($_) } return 1 } my @a=(1,2); print f(@a), " @a\n";' ],
    [ 'a write through a reference, by a callee',
      'sub t { $_[0]++ } sub f { my $o=""; for my $x (@_) { my $r = \$x; $o .= t($$r) } return $o } my @a=(1,2); print f(@a), " @a\n";' ],
    [ 'the iterator chopped',
      'sub f { for my $x (@_) { chop $x } return 1 } my @a=(12,23); print f(@a), " @a\n";' ],
) {
    like +(produce($case->[1]))[1], $ARGS, "$case->[0] over \@_: refused by name";
}

# A closure over the iterator is a fresh variable per pass, refused for that.
like +(produce('sub f { for my $x (@_) { sub { $x = 5 }->() } return 1 } my @a=(1,2); print f(@a), " @a\n";'))[1],
    qr/GAP: an anonymous sub closing over \$x is not yet lowered -- it is built once per pass/,
    'the iterator assigned by a closure over @_: refused by name';

# Reading the iterator over @_ writes nothing back.
round_trips(<<'SRC', 'a sum over @_');
sub f { my $s = 0; for my $x (@_) { $s += $x } return $s } my @a=(1,2); print f(@a), " @a\n";
SRC

round_trips(<<'SRC', 'a reference to the iterator over @_, only read');
sub f { my @o; for my $x (@_) { my $r = \$x; push @o, $$r + 1 } return "@o" } my @a=(1,2); print f(@a), " @a\n";
SRC

round_trips(<<'SRC', 'the iterator over @_ passed to a reader');
sub t { $_[0]*2 } sub f { my $o=""; for my $x (@_) { $o .= t($x) } return $o } my @a=(1,2); print f(@a), " @a\n";
SRC

round_trips(<<'SRC', 'an implicit $_ over @_ passed to a reader');
sub t { $_[0]*2 } sub f { my $o=""; for (@_) { $o .= t($_) } return $o } my @a=(1,2); print f(@a), " @a\n";
SRC

round_trips(<<'SRC', 'a write through the iterator over @_, a reference');
sub f { for my $l (@_) { $$l = 3 } return 1 } my $z = 1; my @a=(\$z); print f(@a), " $z\n";
SRC

round_trips(<<'SRC', 'an element of the iterator over @_ read');
sub f { my $t; for my $l (@_) { my $v = $l->[0]; $t .= $v } return $t } print f([1],[2]), "\n";
SRC

round_trips(<<'SRC', 'a push from @_');
sub f { my @c; for my $x (@_) { push @c, $x * 2 } return "@c" } my @a=(1,2); print f(@a), " @a\n";
SRC

# A LEXICAL SUB CALLEE IS JUDGED BY ITS BODY, as a named one is: one that
# only reads its argument lets a loop over @_ translate, and one that writes
# or keeps it refuses.
round_trips(<<'SRC', 'a lexical sub reading the iterator over @_');
use v5.36; my sub c { my ($s) = @_; $s * 2 } sub e { my $t = 0; for my $x (@_) { $t += c($x) } $t } my @a = (1, 2); print e(@a), " @a\n";
SRC
round_trips(<<'SRC', 'a lexical sub with a signature, mapped over @_');
use v5.36; my sub c ($s) { $s =~ s/1/9/; "[$s]" } sub e { join ",", map { c($_) } @_ } my @a = ("a1", "b1"); print e(@a), " @a\n";
SRC
like +(produce('use v5.36; my sub w { $_[0]++ } sub e { w($_) for @_; 1 } my @a = (1, 2); e(@a); print "@a\n";'))[1],
    $ARGS, 'a lexical sub writing the iterator over @_: refused by name';
like +(produce('use v5.36; my sub r { \$_[0] } our $K; sub e { for my $x (@_) { $K = r($x) } 1 } my @a = (1, 2); e(@a); $$K = 7; print "@a\n";'))[1],
    qr/$CALL|$ARGS/, 'a lexical sub returning a reference to the iterator over @_: refused by name';

done_testing;
