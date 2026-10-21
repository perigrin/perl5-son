# ABOUTME: A foreach over a bare-declared array no call can reach lowers with calls in
# ABOUTME: its body; one a call may reach -- a reference, a closure, an argument -- refuses.

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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    if (!$data || $err =~ /skipped/) {
        fail "$name: translates"; diag $err; return;
    }
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


sub refuses ($src, $why, $name) {
    graph_of($src);
    like producer_stderr(), $why, $name;
}

# A CALL IN THE BODY REFUSED EVERY UNPROVEN LIST, as one that might reach
# the list behind the iterator's back. A `my @a` filled by push is unproven
# only because its binding carries no stamp; if nothing takes a reference
# to it, captures it, or passes it, no callee can reach it. Eleven of
# chalk's graphs -- DCE::run's `for my $dead_id (@dead_ids)` among them --
# refused for a reach they could not have.
round_trips(<<'SRC', 'a private array iterated with method calls');
package F { sub new { bless { n => { a => 1, b => 2, c => 3 } }, shift } sub get { $_[0]{n}{$_[1]} } sub drop { delete $_[0]{n}{$_[1]} } }
my $f = F->new; my @dead;
for my $k (sort keys $f->{n}->%*) { push @dead, $k unless $k eq 'b' }
my @got;
for my $d (@dead) { push @got, $f->get($d); $f->drop($d) }
print "@got ", join(",", sort keys $f->{n}->%*), "\n";
SRC

round_trips(<<'SRC', 'a private array and a sub called on each element');
sub sq { $_[0] * $_[0] }
my @n; push @n, $_ for 1 .. 4;
my $s = 0;
for my $x (@n) { $s += sq($x) }
print "$s\n";
SRC

# A CALL THAT CAN REACH THE LIST still refuses. perl's iterator is the
# element; the lowering's is an index read, and a callee that shifts the
# list moves the next element under it -- measured with the refusal lifted,
# `13` for perl, `24` emitted. A closure over the list lost every element.
# NOW LOWERED: the iterator is aliased by reference -- see
# t/deparse-a-foreach-alias-is-a-reference.t.
round_trips(<<'SRC', 'a reference to the list, handed to a call');
sub drop { shift @{$_[0]} }
my @a; push @a, 1, 2, 3, 4; my $r = \@a;
for my $x (@a) { drop($r); print $x }
print " @a\n";
SRC

round_trips(<<'SRC', 'a closure over the list, called in the body');
my @a; push @a, 1, 2;
my $grow = sub { push @a, 9 if @a < 3 };
for my $x (@a) { $grow->(); print $x }
print "\n";
SRC

# (The list's elements are passed by alias, and the callee writes the
# iterator's own element through @_; perl prints 7 for it.)
round_trips(<<'SRC', 'the list passed to a call');
sub grow { push @{$_[0]}, 0; $_[1] = 7 }
my @a; push @a, 1, 2; my @b;
for my $x (@a) { grow(\@b, @a); print $x }
print " @a|@b\n";
SRC

# A HASH ELEMENT READ AND STORE IN THE BODY was refused here because every
# loop read the element after the loop at the body's version -- `$h{a}++`
# then `$h{a}` gave 2 for 3. The loop carries its memory now, and the read
# after it is its own (t/deparse-a-loop-carries-its-stores.t). chalk's
# Context::cfg_state is this shape, over a file array a method reads.
round_trips(<<'SRC', 'a hash element counted over an unproven list');
my @k; push @k, qw(a b a c a);
my %h;
for my $k (@k) { $h{$k}++ }
print join(",", map { "$_=$h{$_}" } sort keys %h), " $h{a}\n";
SRC
round_trips(<<'SRC', 'a guarded //= of a hash element over an unproven list');
my @k; push @k, qw(a b c);
my %ann = (a => 1, c => 3); my %s = (c => 9);
for my $k (@k) { $s{$k} //= $ann{$k} if exists $ann{$k} }
print join(",", map { "$_=$s{$_}" } sort keys %s), "\n";
SRC

# A NESTED LOOP OVER ANOTHER LIST cannot reach a private one, and with a
# lexical iterator outside it rebinds nothing the outer pass reads. DCE::run
# walks each dead node's inputs, and each input's elements, so.
round_trips(<<'SRC', 'nested loops over other lists inside a private one');
my %in = (a => [[1, 2], 3], b => [4]); my @dead; push @dead, qw(a b);
my @seen;
for my $d (@dead) { for my $i ($in{$d}->@*) { if (ref $i) { for my $e ($i->@*) { push @seen, "$d$e" } } else { push @seen, "$d$i" } } }
print "@seen\n";
SRC
round_trips(<<'SRC', 'a map and a grep inside a private list');
my @w; push @w, qw(ab cde f);
my @out;
for my $w (@w) { push @out, join "", grep { $_ ne "c" } map { uc } split //, $w }
print "@out\n";
SRC

# ONE OVER THE SAME LIST writes, through its alias, an element the outer
# pass has read -- `00` for perl's `10` when the outer read was a copy.
# Read through a reference to its element, the outer pass has what perl has.
round_trips(<<'SRC', 'a nested loop over the outer list');
my @a; push @a, 1, 2; my $s = "";
for my $x (@a) { $s .= $x; $_ = 0 for @a }
print "$s|@a\n";
SRC

# UNDER `$_` A NESTED map LOCALISES IT, and the outer pass's is back after.
round_trips(<<'SRC', 'a nested map under an outer $_');
my @a; push @a, 1, 2;
for (@a) { my @m = map { $_ * 2 } (3, 4); print "$_:@m," }
print "\n";
SRC

# A WRITE TO ANOTHER AGGREGATE'S ELEMENT, or a shift of another array,
# cannot move a private list's elements. chalk's _deserialize_graph fills
# one array while it walks another.
round_trips(<<'SRC', 'element writes and a shift on other arrays');
my @src; push @src, 3, 1, 2; my @dst; my @q = (9, 8);
for my $i (@src) { $dst[$i] = $i * 2; my $h = shift @q; $dst[0] = $h // 0 }
print join(",", map { $_ // "u" } @dst), " @q\n";
SRC

# A WRITE TO THE LIST'S OWN ELEMENT still refuses: perl's iterator aliases
# it, and the lowering's was read at the top of the pass.
round_trips(<<'SRC', 'a write to the iterated element by index');
my @a; push @a, 1, 2, 3; my $i = 0;
for my $x (@a) { $a[$i] = 0; print $x; $i++ }
print " @a\n";
SRC

# A LIST A CLOSURE ONLY PUSHES ONTO stays private. A push adds a pass, which
# perl's iterator and the lowering's index both see; only a shift, splice or
# store could move an element under the index. chalk's Earley drains
# `@pending_sweeps`, which a commit callback fills, with calls in the body.
round_trips(<<'SRC', 'a list a closure only pushes onto, with calls in the body');
package C { sub new { bless { done => {} }, shift } sub is_done { $_[0]{done}{$_[1]} } }
sub f { my $c = C->new; my @pending; my $commit = sub { push @pending, [@_] }; $commit->(1, 3); $commit->(2, 4); $c->{done}{2} = 1;
  my $out = ""; for my $sweep (@pending) { my ($a, $b) = $sweep->@*; for my $sp ($a .. $b) { next if $c->is_done($sp); $out .= $sp } $out .= "|" } @pending = (); return $out }
print f(), "\n";
SRC
round_trips(<<'SRC', 'a closure pushing onto the list from inside its loop');
sub f { my @p = (1); my $add = sub { push @p, $_[0] + 1 if $_[0] < 4 }; my $out = ""; for my $x (@p) { $add->($x); $out .= $x } return $out }
print f(), "\n";
SRC
# THE SAME LIST CARRIED BY AN OUTER LOOP is a Phi, not the pad array, and
# its privacy is the pad array's: Earley drains and clears it per position.
round_trips(<<'SRC', 'a list a closure only pushes onto, drained in an outer loop');
sub f { my @pending; my $commit = sub { push @pending, $_[0] }; my $out = "";
  for my $pos (1 .. 3) { $commit->($pos); $commit->($pos * 10) if $pos == 2;
    if (@pending) { for my $s (@pending) { for my $k (1 .. 2) { $out .= length($s) } $out .= $s } @pending = () } $out .= "|" }
  return $out }
print f(), "\n";
SRC
# A CLOSURE THAT SHIFTS IT moves the next element under the index: refused.
round_trips(<<'SRC', 'a list a closure shifts');
sub f { my @p; my $add = sub { shift @p }; push @p, 1, 2, 3, 4; my $out = ""; for my $x (@p) { $add->(); $out .= $x } return $out }
print f(), "\n";
SRC

# AN ITERATOR THE BODY WRITES, over a private list no call can reach and
# nothing else names: the write-back is perl's alias (chalk's
# LLVM::_process_control_chain, `$ctrl = $ctrl->control_in`).
round_trips(<<'SRC', 'a written iterator walked along a chain, with calls and a push elsewhere');
package N { sub new { bless { id => $_[1], prev => $_[2] }, $_[0] } sub prev { $_[0]{prev} } sub id { $_[0]{id} } }
sub f {
    my ($ret) = @_;
    my @chain; my %seen;
    my @seeds = grep { defined } ($ret->prev);
    for my $ctrl (@seeds) {
        while (defined $ctrl) {
            last if $seen{ $ctrl->id }++;
            push @chain, $ctrl->id;
            $ctrl = $ctrl->prev;
        }
    }
    return "@chain|" . scalar(@seeds);
}
my $c = N->new(1, N->new(2, N->new(3)));
print f(N->new(0, $c)), "\n";
SRC
round_trips(q{package N { sub new { bless { p => $_[1] }, $_[0] } sub p { $_[0]{p} } } sub f { my @s = grep { defined } (N->new(N->new(undef)), undef); my @c; for my $x (@s) { while (defined $x) { push @c, ref $x; $x = $x->p } } return scalar(@c) . "|" . join(",", map { $_ // "u" } @s) } print f(), "\n";},
    'the written-back iterator read after the loop');
# A LIST A CALLEE CAN REACH still refuses.
refuses(q{my @G = (1, 2); sub g { push @G, 9 } sub f { for my $x (@G) { $x .= "y"; g() if $x eq "1y" } return "@G" } print f(), "\n";},
    qr/GAP: a foreach (?:whose body writes its alias and may reshape|over an unproven list)/, 'a written iterator over a list a callee reaches');

done_testing;
