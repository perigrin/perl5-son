# ABOUTME: A method call's argument is an alias, as a sub call's is: the callee
# ABOUTME: may write the caller's variable through @_, so the slot lives in memory.

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

# A METHOD CALL'S entersub HAS NO ex-list: its first kid is the pushmark,
# and the argument scan read the pushmark's (absent) kids and demoted
# nothing. So `$o->m($x)` folded $x to its constant, and a callee writing
# `$_[1]` died "Modification of a read-only value" where perl wrote $x.
round_trips(q{sub m { $_[1] = 9 } my $x = 1; main->m($x); print "$x\n";},
    'a class method writing its argument');
round_trips(q{package O { sub new { bless {}, shift } sub m { $_[1] = 9 } } sub f { my $o = O->new; my $x = 1; $o->m($x); return $x } print f(), "\n";},
    'an instance method writing its argument, in a sub');

# A TERNARY ARGUMENT OF A METHOD CALL passes its arms' pad scalars by alias
# too: chalk's Analysis builds `->new(..., (defined $s ? (superclass => $s)
# : ()))`, refused as a list arm passed by alias.
round_trips(q{package K { sub new { shift; bless {@_}, "K" } } sub f { my ($s, $p) = @_; my $o = K->new(name => "n", (defined $s ? (superclass => $s) : ()), (defined $p ? (parent => $p) : ())); return join ",", map { "$_=$o->{$_}" } sort keys %$o } print f("S", undef), " ", f(undef, "P"), "\n";},
    'optional pairs as a method call\'s arguments');
round_trips(q{package O { sub new { bless {}, shift } sub m { $_[1] = 9 if @_ > 1 } } sub f { my ($c) = @_; my $x = 1; O->new->m($c ? ($x) : ()); return $x } print f(1), f(0), "\n";},
    'a ternary argument the method writes');

# AN ITERATOR PASSED TO A METHOD IS DEMOTED, and its write-back goes to the
# array -- which `my @n = sort ...` bound as the sort itself: the emission
# assigned into `(sort(@n))[$i]`, which perl will not compile (chalk's
# BNF::Target::C). Such an array is built as a container.
round_trips(q{package O { sub m { $_[1] = uc $_[1] if $_[1] eq "b" } } my @n = sort qw(c b a); for my $x (@n) { O->m($x) } print "@n\n";},
    'a sorted array whose iterator a method writes');
round_trips(q{package O { sub m { length $_[1] } } sub f { my @n = sort map { lc } @_; my $t = 0; for my $x (@n) { $t += O->m($x) } return "$t @n" } print f("Bb", "a"), "\n";},
    'a sorted array whose iterator a method only reads');

done_testing;
