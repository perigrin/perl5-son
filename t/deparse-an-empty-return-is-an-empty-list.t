# ABOUTME: A bare `return` or `return ()` gives a list caller nothing and a scalar
# ABOUTME: caller undef; beside a `return @list`, each caller gets its own reading.

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


# `return ()` AND `return` WERE BUILT AS `return undef`: one undef Constant
# for all three, where a list caller gets 0, 0 and 1 elements. Beside a
# `return @c` the exit merge then read as a scalar, and a list caller got the
# count -- chalk's Schedule::Elaborate::_collect_branch_chain returned 1
# where it returned its chain, and its if/else merges lost every phi.
round_trips(<<'SRC', 'return () beside return @list');
sub fill { my ($n, $c) = @_; push @$c, "n$_" for 1 .. $n }
sub chain { my ($n) = @_; return () unless defined $n; my @c; fill($n, \@c); return @c }
my @a = chain(2); my @b = chain(undef);
print scalar(@a), ":@a|", scalar(@b), "\n";
SRC

round_trips(<<'SRC', 'bare return, list and scalar callers');
sub f { my ($n) = @_; return unless $n; return ($n, $n) }
my @a = f(0); my $s = f(0);
print scalar(@a), defined $s ? "def" : "undef", "\n";
SRC

round_trips(<<'SRC', 'return undef is still one element');
sub f { my ($n) = @_; return undef unless $n; return ($n, $n) }
my @a = f(0); print scalar(@a), "\n";
SRC

# THE SCALAR CALLER keeps perl's reading of each exit: the last element of
# `return ($n, $n + 1)`, the count of `return @c`, undef for a bare return.
round_trips(<<'SRC', 'scalar callers of a merged list exit');
sub f { my ($n) = @_; return unless $n; my @c = (1 .. $n); return @c if $n > 5; return ($n, $n + 1) }
my $a = f(0); my $b = f(9); my $c = f(3); my @l = f(3);
print defined $a ? "d" : "u", " $b $c @l\n";
SRC

done_testing;
