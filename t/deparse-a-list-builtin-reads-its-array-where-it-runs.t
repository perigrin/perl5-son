# ABOUTME: A builtin over a whole array -- reverse, sort, join -- reads the array as it
# ABOUTME: stands where the call runs, after a loop that filled it, not before.

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


# `reverse @r` took the array and no memory, so nothing in the graph said it
# reads @r after the loop's pushes; with its result pushed into, the
# declaration was placed above the loop and reversed an empty array. Silent
# on base. chalk's EagerPinning::schedule builds its body so.
round_trips(<<'P', 'reverse of an array a loop filled, then pushed into');
my @r;
push @r, $_ for 1 .. 3;
my @b = reverse @r;
push @b, 9;
print "@b\n";
P

round_trips(<<'P', 'sort and join of an array a loop filled');
my @r;
push @r, $_ for 3, 1, 2;
my @s = sort { $a <=> $b } @r;
push @s, 9;
my @j = (join ",", @r);
push @j, 8;
print "@s|@j\n";
P

round_trips(<<'P', 'a control-chain walk with a region head');
use v5.42.0;
package N { sub new { my ($c, %a) = @_; bless {%a}, $c } sub operation { $_[0]{op} } sub control_in { $_[0]{ci} } sub inputs { $_[0]{in} } sub head { $_[0]{head} } }
package R { our @ISA = ('N') }
package main;
use Scalar::Util qw(blessed);
sub walk {
    my ($exit) = @_;
    my @reverse;
    my $cur = $exit->control_in;
    while (defined $cur && blessed($cur)) {
        last if $cur->operation eq 'Start';
        if ($cur isa R) {
            my $head = $cur->head;
            last unless defined $head;
            push @reverse, $head;
            $cur = $head->control_in;
            next;
        }
        push @reverse, $cur;
        my $next = $cur->control_in;
        if (!defined $next) {
            my $ins = $cur->inputs;
            last unless defined $ins && ref($ins) eq 'ARRAY';
            $next = $ins->[0];
        }
        $cur = $next;
    }
    my @body = reverse @reverse;
    push @body, $exit;
    return join ",", map { $_->operation } @body;
}
my $s = N->new(op => 'Start');
my $a = N->new(op => 'A', ci => $s);
my $h = N->new(op => 'H', ci => $a);
my $r = R->new(op => 'Region', head => $h);
my $b = N->new(op => 'B', in => [$r]);
my $x = N->new(op => 'X', ci => $b);
print walk($x), " ", walk($a), "\n";
P

done_testing;
