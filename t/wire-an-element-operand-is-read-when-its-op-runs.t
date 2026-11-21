# ABOUTME: An element operand is the element itself, not a copy: a store a later operand
# ABOUTME: makes to it is what the op reads. The wire cannot say so; it is refused by name.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

# THE DEFECT (audit 2026-11-19, probe vp5 -- one of the three whose wire was
# byte-identical to a right program's). perl pushes `$a[0]` as the element,
# and `+` reads it when `+` runs:
#
#     my @a = (1,2); my $x = $a[0] + ($a[0] = 10) + $a[0];     perl 30
#
# The walk read the element where its op stood -- a Subscript at the memory
# before the store -- and the wire said 1 + 10 + 10 = 21.
#
# REFUSED, NOT RE-READ. A scalar variable read this way is read again once
# the later operands have run (_reread_alias_operand_stored_later). An
# element is the element only if it EXISTED when it was read: `$h{new} .
# ($h{new} = "q")` pushes undef, not an alias, and reads "" where a second
# read would see "q". The wire has no place to say which, so the shape --
# a direct element read still on the stack when a store into the same
# container is made -- is a GAP, as the package-scalar form already is.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub translate ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return scalar qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>&1 >/dev/null);
}

my $gap = qr/GAP: an element operand is read by alias and a later operand stores into its container/;

like translate('my @a = (1,2); my $x = $a[0] + ($a[0] = 10) + $a[0]; print "$x\n";'),  $gap, 'an array element, added';
like translate('my %h = (a => "p"); my $x = $h{a} . ($h{a} = "q"); print "$x\n";'),    $gap, 'a hash element, joined';
like translate('my $r = [1,2]; my $x = $r->[0] + ($r->[0] = 10); print "$x\n";'),      $gap, 'through a reference';
like translate('my @a = (1,2); my $x = $a[0] + ($a[0] += 10); print "$x\n";'),         $gap, 'a compound store';
like translate('my @a = (1,2); my $x = $a[0] + ($a[0]++); print "$x\n";'),             $gap, 'an increment';
like translate('my @a = (1,2); my @l = ($a[1], $a[0] = 10); print "@l\n";'),           $gap, 'another element of it, in a list';

# A VALUE COMPUTED FROM THE ELEMENT is a copy, and what it read stands.
unlike translate('my @a = (1,2); my $x = ($a[0] + 1) + ($a[0] = 10); print "$x\n";'), qr/GAP/, 'a sum made before the store';
unlike translate('my @a = (1,2); my @b = (5); my $x = $b[0] + ($a[0] = 10); print "$x\n";'), qr/GAP/, 'an element of another array';
unlike translate('my @a = (1,2); $a[0] = $a[0] + 1; my $y = $a[1]; $a[1] = $y; print "@a\n";'), qr/GAP/, 'a read consumed before the store';

# AN ASSIGNMENT'S OWN TARGET is not a later operand, and an element
# dereferenced on the way to a store is not stored.
unlike translate('my @a = (1,2); $a[0] = $a[1]; print "@a\n";'), qr/GAP/, 'an element copied to another';
unlike translate('my @a = (1,2); $a[0] = "$a[0]!"; print "@a\n";'), qr/GAP/, 'an element interpolated into itself';
unlike translate('sub st { $_[0][$_[1]] = "$_[2]!" } my @o = ([]); st($o[0], 0, "x"); print $o[0][0], "\n";'),
    qr/GAP/, 'an element of @_ dereferenced for the store';

# AN ARGUMENT IS MARKED AS AN LVALUE AND IS NOT STORED: perl flags it OPf_MOD
# because it is passed by alias.
unlike translate('sub f { $_[0] } my @r = (1,2); print $r[0], f($r[0]) ? "b" : "-", "\n";'), qr/GAP/, 'an element also passed to a call';
like translate('my @a = (1,2); my @l = ($a[0], $a[0]++); print "@l\n";'), $gap, 'a post-increment in a list';

# A CALL IN A LATER OPERAND may store the element too. Since 2026-11-21 the
# element is read again where the callee's MOD set says it may store into the
# container (t/deparse-an-element-a-later-call-stores-is-read-when-its-op-runs.t);
# REFUSED BY NAME where the callee may reshape the container or replace what
# holds it (an alias to a removed element is not the element at its index),
# or where nothing can be said of the call.
unlike translate('our @a = (0); sub g { $a[0] = $_[0] + 1; $_[0] } print g(1), $a[0], g(0), $a[0], "\n";'), qr/GAP/, 'a package array';
unlike translate('our %h = (k => 0); sub g { $h{k} = $_[0] + 1; $_[0] } print g(1), $h{k}, g(0), $h{k}, "\n";'), qr/GAP/, 'a package hash';
unlike translate('my @a = (0); sub g { $a[0] = $_[0] + 1; $_[0] } print g(1), $a[0], g(0), $a[0], "\n";'), qr/GAP/, 'a lexical array a sub closes over';
unlike translate('my @a = (1); sub g { 0 } print $a[0], g(), $a[0], "\n";'), qr/GAP/, 'a lexical array no sub reaches';
unlike translate('our @a = (1); sub g { 0 } print g(), $a[0], "\n";'), qr/GAP/, 'the call before the element';
my $reshape = qr/GAP: an element operand is read by alias and a later operand calls a sub that may reshape its container or replace what holds it/;
my $unknown = qr/GAP: an element operand is read by alias and a later operand calls code whose stores cannot be known here/;
like translate('my $r = [1, 2]; sub f { shift @$r; "" } print $r->[0], f(), "\n";'), $reshape, 'a shift through a reference';
like translate('my $r = {k => 1}; sub f { delete $r->{k}; "" } print $r->{k}, f(), "\n";'), $reshape, 'a delete';
like translate('our @a = (1); sub f { @a = (7); "" } print $a[0], f(), "\n";'), $reshape, 'a list assign of the array';
like translate('my $r = [1]; sub f { $r = [7]; "" } print $r->[0], f(), "\n";'), $reshape, 'the reference replaced';
like translate('my $r = {a => {b => 1}}; sub f { $r->{a} = {}; "" } print $r->{a}{b}, f(), "\n";'), $reshape, 'an inner reference replaced';
like translate('my $r = [1]; sub f { 0 } my $c = $ARGV[0] ? \&f : sub { 1 }; print $r->[0], $c->(), "\n";'), $unknown, 'a code ref of two subs';
like translate('my $r = [1]; print $r->[0], eval "2", "\n";'), $unknown, 'a string eval';
like translate('my $r = [1]; my $m = "x"; print $r->[0], main->$m(), "\n";'), $unknown, 'a dynamic method';

done_testing;
