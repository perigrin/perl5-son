# ABOUTME: An element operand is the element itself: a later call operand that may store into
# ABOUTME: its container (what the callee may write, transitively) makes the op read it again.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

# THE DEFECT (audit probe ag30, both wires). perl pushes `$r->[0]` itself,
# so print reads it after every later operand has run:
#
#     my $r = [0]; sub f { $r->[0] = $_[0] + 1; $_[0] }
#     print f(1), $r->[0], f(0), $r->[0];                         perl 1101
#
# The walk read the element where its op stood and said 1201. An element is
# the element only if it EXISTED when pushed (else perl pushes undef), so the
# second read is taken only where an exists made where the first read stood
# says so. Which calls may store into the container is each sub's write
# (MOD) set, through the subs it calls (SoN::FromOptree::ModSets).

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

sub refused ($src, $why, $name) {
    graph_of($src);
    like producer_stderr(), $why, $name;
}

# A CALL THAT STORES THE ELEMENT, through a reference.
my $f = 'my $r = [0]; sub f { $r->[0] = $_[0] + 1; $_[0] } ';
round_trips($f . 'print f(1), $r->[0], f(0), $r->[0], "\n";',              'ag30: print');
round_trips($f . 'my @l = (f(1), $r->[0], f(0), $r->[0]); print "@l\n";',  'a list assignment');
round_trips($f . 'print join(",", $r->[0], f(7)), "\n";',                  'join');
round_trips($f . 'print $r->[0] + f(4), "\n";',                            'an addition');
round_trips('my $h = {k => 0}; sub g { $h->{k} = $_[0] + 1; $_[0] } print g(1), $h->{k}, g(0), $h->{k}, "\n";',
    'a hash element through a reference');

# AN ELEMENT THAT DID NOT EXIST when pushed is undef, whatever the call stores.
round_trips('my $r = []; sub f { $r->[0] = 5; "" } my @l = ($r->[0], f()); print $l[0] // "u", "\n";',
    'an element made by the call');
round_trips('my $h = {}; sub f { $h->{k} = 5; "" } my @l = ($h->{k}, f()); print $l[0] // "u", "\n";',
    'a key made by the call');

# A CALL THAT PROVABLY DOES NOT STORE IT: what was read stands.
round_trips('my $r = [3]; sub f { 0 } print $r->[0], f(), "\n";',          'a call that stores nothing');
round_trips('my $r = {a => 3}; sub f { $r->{b} = 9; 0 } print $r->{a}, f(), "\n";', 'another key');

done_testing;
