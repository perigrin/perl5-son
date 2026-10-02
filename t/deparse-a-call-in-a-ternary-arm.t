# ABOUTME: A call in a ternary arm runs only when that arm is taken: the arm is a branch,
# ABOUTME: and the value merges -- in a sub, in a map body, and recursively.

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


# A CALL IS PINNED WHERE IT RUNS, and a ternary whose arm calls built a value
# select with the call outside it: the call ran on every pass. In a map body
# chalk's Node::_serialize_inputs called ->id() on the undef element it was
# guarding against; in a plain sub the second control successor refused
# ("a control node with 2 successors"), which is fib.
round_trips(<<'SRC', 'a recursive call in a ternary arm');
sub fib { my $n = shift; return $n < 2 ? $n : fib($n-1) + fib($n-2) } print fib(10), "\n";
SRC

round_trips(<<'SRC', 'a guarded call in a ternary in a map');
use v5.42; sub f ($x) { return "f$x" }
sub ids ($in) { my @ids = map { defined($_) ? f($_) : "undef" } $in->@*; return join(",", @ids) }
print ids([1, undef, 3]), "\n";
SRC

round_trips(<<'SRC', 'a guarded method call in a ternary in a map');
use v5.42; use experimental 'class';
class N { field $id :param :reader; }
sub ids ($in) { my @ids = map { defined($_) ? $_->id() : "undef" } $in->@*; return join(",", @ids) }
print ids([N->new(id => 1), undef, N->new(id => 3)]), "\n";
SRC

round_trips(<<'SRC', 'a call in each arm');
my $n = 0; sub a { $n += 1; return "a" } sub b { $n += 10; return "b" }
sub run { return map { $_ % 2 ? a() : b() } @_ } my @r = run(1, 2, 3); print "@r $n\n";
SRC

round_trips(<<'SRC', 'a call in the false arm only');
my $n = 0; sub b { $n++; return "b" } sub pick { my $x = shift; return $x ? "t" : b() }
print pick(1), pick(0), pick(1), " $n\n";
SRC

done_testing;
