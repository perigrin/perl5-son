# ABOUTME: A grep whose body may write $_ through a call, over an array a sort
# ABOUTME: filled, reads the array: the sort result is a list, not a reference.

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

# A TOPIC ALIAS MARKED THE SORT CALL a mutated literal, and the next read of
# `@r` dereferenced the call: `(sort(@x))->@*` died "Can't use an undefined
# value as an ARRAY reference" (chalk's BNF::Target::C::_emit_nullable_set).
round_trips(<<'SRC', 'a grep calling a method, over an array a sort filled');
use v5.42; use experimental 'class';
package O { sub new { bless {n=>$_[1]}, $_[0] } sub name { $_[0]{n} } sub isn { $_[1] =~ /a/ } }
class K { field $g :param; field $d :param;
  method f() { my @r = sort map { $_->name() } $g->@*; my @n = grep { $d->isn($_) } @r; return "@n" } }
print K->new(g => [O->new("ba"), O->new("x"), O->new("aa")], d => O->new("z"))->f, "\n";
SRC

done_testing;
