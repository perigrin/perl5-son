# ABOUTME: An array's count read before a push is the count before it: the Count carries
# ABOUTME: the memory version it read at, and spelled at its use it counted the push too.

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

# chalk's LR0DFA::_register_state: `my $state_id = scalar @states; ...;
# push @states, {...}; return $state_id` returned one more than perl, and
# every goto target pointed one state on.
round_trips(q{my @s; sub r { my $sid = scalar @s; push @s, 1; return $sid } print r(), r(), "\n";},
    'a count read before a push, returned after it');
round_trips(q{my @s; my %g; sub r { my $k = shift; return $g{$k} if exists $g{$k}; my $sid = scalar @s; $g{$k} = $sid; push @s, 1; return $sid } print r(1), r(2), r(1), "\n";},
    'the same after a guarded early return');
round_trips(<<'SRC', 'a count of a field array read before a push in a method');
use v5.42.0;
use experimental 'class';
class Reg { field @states; field %reg;
  method add ($k) { return $reg{$k} if exists $reg{$k}; my $sid = scalar @states; $reg{$k} = $sid; push @states, { id => $sid }; return $sid }
  method count () { scalar @states } }
my $r = Reg->new; print join(",", $r->add("a"), $r->add("b"), $r->add("a"), $r->count), "\n";
SRC

# The LR0DFA shape itself: a loop between the read and the push reads the
# store that took the count as its memory version.
round_trips(<<'SRC', 'a count read before a loop and a push in a method');
use v5.42.0;
use experimental 'class';
class Reg { field @states; field %reg;
  method add ($ids) { my $key = join(",", @$ids); return $reg{$key} if exists $reg{$key}; my $sid = scalar @states; $reg{$key} = $sid; my %t; for my $c (@$ids) { next if $c > 5; push @{ $t{$c % 2} //= [] }, $c } push @states, { id => $sid, t => \%t }; return $sid } }
my $r = Reg->new; print join(",", $r->add([1,2]), $r->add([3]), $r->add([1,2]), $r->add([7])), "\n";
SRC

done_testing;
