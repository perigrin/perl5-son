# ABOUTME: `\ f()` is a reference to each value the call returns, not to an array
# ABOUTME: holding them -- so `"${\ $o->m}"` interpolates the value, as chalk spells it.

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

# THE CALL'S RESULT IS BOUND TO AN ARRAY, and a Ref over it took `\@eff`:
# a reference to that array, which `${...}` refused ("Not a SCALAR
# reference"). perl's `\ f()` is the refgen of a list: one reference per
# returned value, the last of them in scalar context.
round_trips(q{package N { sub new { bless { v => $_[1] }, $_[0] } sub value { $_[0]{v} } }
    my $n = N->new(7); my $s = "${\$n->value}"; print "$s\n";},
    'a scalar deref of a reference to a method call');
round_trips(q{sub two { (4, 5) } my $r = \ two(); print "$$r\n"; my @r = \ two(); print scalar(@r), " ${$r[0]}\n";},
    'a reference to a list call, scalar and list');
round_trips(q{sub v { 9 } my @a = (v => "${\ v()}"); print "@a\n";},
    'inside a list');

# IN SCALAR CONTEXT THE REFGEN IS ONE REFERENCE, the last value's, and a
# loop carrying it carries a scalar: stamped as a list, the Phi became an
# array and `$$r` dereferenced its count ("Can't use string (\"3\")").
round_trips(q{sub g { (5,6,7) } my $r = 0; for my $i (1,2) { $r = \ g() } print "$$r\n";},
    'a reference to a list call carried by a for loop');
round_trips(q{sub g { (5,6,7) } my $r = 0; my $i = 0; while ($i++ < 2) { $r = \ g() } print "$$r\n";},
    'a reference to a list call carried by a while loop');
round_trips(q{my @a = (5,6,7); my $r = 0; for my $i (1,2) { $r = \(@a) } print "$$r\n";},
    'a reference to each element of an array carried by a loop');

done_testing;
