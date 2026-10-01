# ABOUTME: `scalar(@{ EXPR })` counts the aggregate EXPR refers to, whatever EXPR is --
# ABOUTME: a call, a shift, a variable -- rather than yielding the reference itself.

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

# THE COUNT HANDLER KEPT AN ALLOW-LIST of operand kinds (padsv, gvsv, helem,
# aelem), and anything else fell through with the rv2av dropped: the count
# was the reference. perl 2, emitted ARRAY(0x...).
round_trips(<<'SRC', 'the count of a call result');
sub r { my @x = (1, 2); return \@x } print scalar(@{ r() }), "\n";
SRC

round_trips(<<'SRC', 'the count of a call result, bound');
sub r { my @x = (1, 2, 3); return \@x } my $n = @{ r() }; print "$n\n";
SRC

round_trips(<<'SRC', 'the key count of a hash a call returns');
sub r { my %x = (a => 1, b => 2); return \%x } print scalar(%{ r() }), "\n";
SRC

round_trips(<<'SRC', 'the count of a shifted argument');
sub n { return scalar(@{ shift() }) } print n([4, 5, 6]), "\n";
SRC

round_trips(<<'SRC', 'the count through a variable, unchanged');
my $r = [1, 2]; print scalar(@$r), "\n";
SRC

# THE LIST-CONTEXT DEREF HAD THE SAME ALLOW-LIST (const, padsv), so `@$_`
# over a map's topic flattened to the reference itself: the inner map ran
# once, over the ref, and doubled its address. perl `2 4|6`.
round_trips(<<'SRC', 'a nested map over the outer topic');
sub f { my @a = map { join(" ", map { $_ * 2 } @$_) } @_; return join("|", @a) } print f([1, 2], [3]), "\n";
SRC

round_trips(<<'SRC', 'a list deref of a call result');
sub r { return [4, 5] } my @l = @{ r() }; print "@l\n";
SRC

round_trips(<<'SRC', 'a hash deref of a call result in list context');
sub r { return { a => 1 } } my %h = %{ r() }; print join(",", %h), "\n";
SRC

# A LOOP TOPIC PASSED TO A CALL is OPf_MOD -- an argument is passed by
# alias -- and the read took that for a store target: a name token,
# `$main::_`, where the map's element was bound. `map { f($_) }` called f
# with the global (chalk's emitted lib/ ran many such maps).
round_trips(<<'SRC', 'a map topic passed to a sub');
sub f { uc shift } my @r = map { f($_) } qw(a b); print "@r\n";
SRC

round_trips(<<'SRC', 'a foreach topic passed to a method');
package O; sub new { bless {}, shift } sub g { uc $_[1] }
package main; my $o = O->new; my $s = ""; for (qw(a b)) { $s .= $o->g($_) } print "$s\n";
SRC

round_trips(<<'SRC', 'a grep topic passed to a sub');
sub big { $_[0] > 2 } sub keep { grep { big($_) } @_ } my @r = keep(1 .. 5); print "@r\n";
SRC

# A TOPIC STORE STAYS A STORE: the write-back to the element still goes
# through the name.
round_trips(<<'SRC', 'a foreach topic assigned in the body');
my @a = (1, 2); for (@a) { $_ = $_ * 10 } print "@a\n";
SRC

# A LEXICAL PASSED TO A CALL is OPf_MOD for the same reason, and the read
# became a name token -- harmless only while the lexical holds its value in
# the emission. A loop counter, or a call result bound to a `my`, lives in
# the graph instead: chalk's CoreItemIndex called `register($name,
# $alt_idx, $dot)` with three variables nothing assigned.
round_trips(<<'SRC', 'loop variables and a bound call result passed to a method');
package R; sub new { bless {}, shift } sub reg { shift; join ":", @_ }
sub nm { "r" }
package main; my $o = R->new; my @out;
for my $i (0 .. 1) { my $name = R::nm(); for my $d (0 .. 1) { push @out, $o->reg($name, $i, $d) } }
print "@out\n";
SRC

round_trips(<<'SRC', 'a lexical passed to a sub that only reads it');
sub twice { $_[0] * 2 } my @r; for my $n (1 .. 3) { push @r, twice($n) } print "@r\n";
SRC

# A DEMOTED ITERATOR LIVES IN ITS SLOT. Passing a loop variable to a sub
# demotes it -- the argument is an alias the callee may write -- and the
# loop's value then has to be in the slot each pass, and a write through
# $_[0] has to reach what the variable aliases.
round_trips(<<'SRC', 'a range iterator a callee writes through $_[0]');
sub bump { $_[0]++ } my $s = ""; for my $n (1 .. 3) { bump($n); $s .= $n } print "$s\n";
SRC

round_trips(<<'SRC', 'an array iterator passed to a sub that reads it');
sub twice { $_[0] * 2 } my @a = (1, 2, 3); my @r; for my $x (@a) { push @r, twice($x) } print "@r\n";
SRC

round_trips(<<'SRC', 'an array iterator a callee writes: the element changes');
sub bump { $_[0]++ } my @a = (1, 2); for my $x (@a) { bump($x) } print "@a\n";
SRC

# THE LAST INDEX OF A REFERENCED ARRAY -- `$#$r`, `$#{$r}`, `$r->$#*` --
# fell through to the op table's `Length` and rendered `length($r)`: the
# string length of the reference's address. chalk's CoreItemIndex looped
# `for my $alt_idx (0 .. $expressions->$#*)` and ran ~20 times over 2.
round_trips(<<'SRC', 'the last index through a reference, three spellings');
sub f { my $r = $_[0]; return join ",", $#$r, $#{$r}, $r->$#* } print f([5, 6, 7]), "\n";
SRC

round_trips(<<'SRC', 'a range to the last index of a reference');
sub f { my $r = $_[0]; my @o; for my $i (0 .. $r->$#*) { push @o, $r->[$i] } "@o" } print f([5, 6, 7]), "\n";
SRC

round_trips(<<'SRC', 'the last index of an empty referenced array');
sub f { my $r = $_[0]; return $#$r } print f([]), "\n";
SRC

# A DEREF A SUB RETURNS takes the CALLER'S context -- want 0 on the rv2av --
# and the list-deref handler asked for LIST (3) only, so the deref was
# dropped and the sub returned the reference: chalk's MOP::Field
# `method attributes() { return $attributes->@* }` handed back one ARRAY ref,
# and chalk's compiler then miscompiled every class with a field.
round_trips(<<'SRC', 'a returned array deref, three spellings');
sub a { my $r = shift; return $r->@* } sub b { my $r = shift; $r->@* } sub c { my $r = shift; return @$r }
my @x = a([1, 2]); my @y = b([3, 4, 5]); my @z = c([6]); print scalar(@x), scalar(@y), scalar(@z), "\n";
SRC

round_trips(<<'SRC', 'a returned array deref read in scalar context');
sub a { my $r = shift; return $r->@* } my $n = a([7, 8, 9]); print "$n\n";
SRC

round_trips(<<'SRC', 'a returned hash deref');
sub h { my $r = shift; return %$r } my %c = h({ k => 1, j => 2 }); print join(",", map { "$_=$c{$_}" } sort keys %c), "\n";
SRC

# A CALL IN SCALAR CONTEXT OF A LIST-STAMPED SUB is bound to a scalar: its
# recorded `want` outranks the callee's inferred stamp. Bound to an array,
# `my $count = items([4, 5])` ran the call in list context and printed the
# elements, 45, where perl prints the count (found by the corpus case for
# the returned deref, once the deref itself was fixed).
round_trips(<<'SRC', 'a list-returning sub called in scalar context and read later');
sub items { my $r = shift; return $r->@* }
my @got = items([1, 2, 3]); my $count = items([4, 5]);
print scalar(@got), " ", $count, "\n";
SRC

done_testing;
