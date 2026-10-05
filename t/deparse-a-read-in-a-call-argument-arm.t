# ABOUTME: A lexical read in an arm of a ternary or short-circuit passed to a sub is a
# ABOUTME: read: its bound value, not an unbound name -- perl flags it OPf_MOD by alias.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

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


# PERL FLAGS EVERY CALL ARGUMENT OPf_MOD, the arms of a ternary argument
# included (`padsv sM` under cond_expr under the entersub). The read was
# recognised as an argument only when its parent, past nulls, WAS the
# entersub, so an arm's read became an unbound PadAccess and the emission
# passed an undeclared variable. chalk's NodeFactory::make builds every Phi
# with `inputs => (defined $values ? $values : [])` -- each got undef, and
# 51 of chalk's test files failed against the emitted lib/.
round_trips(<<'SRC', 'a ternary argument whose arm reads a lexical');
sub n { $_[0] }
sub f { my $v = shift; print n($v ? $v : "s"), "\n" }
f("a"); f();
SRC

round_trips(<<'SRC', 'a ternary argument among others, defaulting a reference');
sub n { scalar @{ $_[1] } }
sub f { my %a = @_; my $v = delete $a{x}; return n("i", (defined $v ? $v : [])) }
print f(x => [1, 2]), f(), "\n";
SRC

round_trips(<<'SRC', 'a short-circuit argument whose right side reads a lexical');
sub n { $_[0] }
sub f { my ($v, $w) = @_; print n($v || $w), n($v && $w), "\n" }
f("a", "b"); f(0, "c");
SRC

round_trips(<<'SRC', 'a method argument');
package O { sub new { bless {}, shift } sub n { $_[1] } }
sub f { my $v = shift; my $o = O->new; print $o->n(defined $v ? $v : "u"), "\n" }
f("a"); f();
SRC

done_testing;
