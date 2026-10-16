# ABOUTME: A function exit merging a returned call's list with a scalar from another path
# ABOUTME: refuses: which one the caller gets depends on its context, decided at run time.

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


sub render_gap ($src) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {});
    return defined $out ? '' : ($d->gap // '');
}

# `if ($x) { return g() } return 7`: g runs in the caller's context, but the
# exit's variable was a scalar, so the arm bound g's list and assigned its
# COUNT -- a list caller got (3), not (1, 2, 3). Silent on base. chalk's
# EagerPinning::_expand_node returns _expand_if's items so.
like render_gap(<<'P'), qr/a call returned in the caller.s context is bound to one/,
sub g { return (1, 2, 3) }
sub f { my ($x) = @_; if ($x) { return g(); } return 7; }
my @a = f(1); my @b = f(0);
print scalar(@a), scalar(@b), "\n";
P
    'a returned call beside a returned scalar refuses, naming its cause';

like render_gap(<<'P'), qr/a call returned in the caller.s context is bound to one/,
sub g { return (1, 2, 3) }
sub f { my ($x) = @_; return g() if $x; return 7; }
my @a = f(1);
print scalar(@a), "\n";
P
    'the statement-modifier spelling refuses too';

# BESIDE A LIST TOO: the exit's scalar reading of the call's path took the
# list's count, where perl's scalar call of g gives its last value -- 3
# against 6. It matched only while g's list was (1, 2, 3).
like render_gap(<<'P'), qr/a call returned in the caller.s context is bound to one/,
sub g { return (4, 5, 6) }
sub f { my ($x) = @_; if ($x) { return g(); } return (7, 8); }
my @a = f(1); my $s = f(1);
print scalar(@a), $s, "\n";
P
    'a returned call beside a returned list refuses for its scalar reading';

# A METHOD CALL RETURNED IN AN ARM is bound to the exit's scalar too: no
# `want` on the Call says it runs in the caller's context, and a list caller
# got its last value alone. chalk's EagerPinning::_expand_node. Only a callee
# whose graph is here and returns a list refuses; one that is not here is
# taken for a scalar, as it was.
like render_gap(<<'P'), qr/a call returned in the caller's context is bound to one/,
package O {
    sub new { bless {}, shift }
    sub items { return (4, 5, 6) }
    sub f { my ($o, $x) = @_; if ($x) { return $o->items } return 7 }
}
my @a = O->new->f(1); my $s = O->new->f(1);
print scalar(@a), $s, "\n";
P
    'a returned method call beside a returned scalar refuses, naming its cause';

# A call whose context the program states is a value like any other.
round_trips(<<'P', 'a scalar method call returned beside a scalar');
package O { sub new { bless {}, shift } sub n { return 4 } }
sub f { my ($o, $x) = @_; if ($x) { my $v = $o->n; return $v } return 7 }
print f(O->new, 1), f(O->new, 0), "\n";
P

# The call the only exit: the caller's context reaches the call.
round_trips(<<'P', 'a returned call alone');
sub g { return (1, 2, 3) }
sub f { return g() }
my @a = f(1); my $s = f(1);
print scalar(@a), $s, "\n";
P

done_testing;
