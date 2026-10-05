# ABOUTME: A copy of an aggregate that is changed through a reference -- passed to a sub
# ABOUTME: as \%m or \@m -- stays a copy: the source does not see the change.

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


# A COPY THE SUB MUTATES IS COPIED; one it never mutates keeps the alias.
# The mutation scan saw shift/push/delete and element stores, not a
# reference taken to the aggregate -- and `add(\%m)` mutates %m as surely
# as `$m{b} = 2`. The copies collapsed onto their source: chalk's
# Schedule::Elaborate::_elaborate_if copies `%pre` into `%then_map` and
# `%else_map`, elaborates each through a reference, and compares them --
# all three were the caller's map, and every if/else lost its phi.
round_trips(<<'SRC', 'a hash copy changed through a reference');
sub add { my ($h) = @_; $h->{b} = 2 }
sub f { my ($v) = @_; my %pre = %$v; my %m = %pre; add(\%m);
        return join(",", sort keys %pre) . "|" . join(",", sort keys %m) . "|" . join(",", sort keys %$v) }
print f({a => 1}), "\n";
SRC

round_trips(<<'SRC', 'an array copy changed through a reference');
sub add { my ($a) = @_; push @$a, 2 }
sub f { my ($v) = @_; my @pre = @$v; my @m = @pre; add(\@m); return "@pre|@m|@$v" }
print f([1]), "\n";
SRC

round_trips(<<'SRC', 'a reference held in a variable');
sub f { my ($v) = @_; my %m = %$v; my $r = \%m; $r->{b} = 2; return join(",", sort keys %m) . "|" . join(",", sort keys %$v) }
print f({a => 1}), "\n";
SRC

done_testing;
