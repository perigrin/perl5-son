# ABOUTME: A scalar operand is the variable itself: a later operand that stores it through an
# ABOUTME: argument (a callee's `$_[0] = ...`), chomp, s/// or a list assignment is what the op reads.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

# THE GAP (marked in _reread_alias_operand_stored_later, 2026-11-21): a scalar
# operand was read again after a later direct store (=, op=, ++/--) or a call
# that reaches it by name, but not after
#
#     my $x = 1; sub g { $_[0] = 5; "" } print $x, g($x);      perl 5
#     my $x = "a\n"; print $x, chomp($x);                      perl a1
#
# The first is the callee's MOD set (it stores its arguments); the second a
# builtin that stores its operand (B::SoN::EffectTable::stores_operands).

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

# A CALLEE THAT STORES ITS ARGUMENT.
round_trips('my $x = 1; sub g { $_[0] = 5; "" } print $x, g($x), "\n";',        'a lexical passed and stored');
round_trips('our $x = 1; sub g { $_[0] = 5; "" } print $x, g($x), "\n";',       'a package scalar passed and stored');
round_trips('my $x = 1; sub h { $_[0] .= "!"; "" } sub g { h(@_) } print $x, g($x), "\n";', 'stored two calls down');
round_trips('my @a = (0); sub g { $_[0] = 5; "" } print $a[0], g(@a), "\n";',   'an array element passed in its array');
round_trips('my @a = (0); sub g { $_[0] = 5; "" } print $a[0], g($a[0]), "\n";', 'an array element passed');
round_trips('my $x = 1; sub g { my $y = $_[0]; $y = 5; "" } print $x, g($x), "\n";', 'a callee that copies its argument');

# A BUILTIN THAT STORES ITS OPERAND, and a list assignment.
round_trips('my $x = "a\n"; print $x, chomp($x), "\n";',                         'chomp');
round_trips('my $x = "ab"; print $x, chop($x), "\n";',                           'chop');
round_trips('my $x = "a"; print $x, ($x =~ s/a/b/), "\n";',                      's///');
round_trips('my $x = "a"; print $x, ($x =~ tr/a/b/), "\n";',                     'tr///');
round_trips('my $x = 1; my $y; my $s = $x . (($x, $y) = (5, 6)); print "$s\n";', 'a list assignment');
round_trips('our $x = "a\n"; print $x, chomp($x), "\n";',                        'chomp of a package scalar');

done_testing;
