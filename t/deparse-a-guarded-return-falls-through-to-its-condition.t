# ABOUTME: A sub whose last statement is `return X if C` returns C when C fails -- the
# ABOUTME: guard's own value, not whatever the statement before it left behind.

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


# `return X if C` IS `C and return X`, and as the sub's last statement the
# `and` takes the caller's context: when C fails, its value -- C -- is the
# sub's. The producer discarded it ("return X if C yields nothing", true
# only in void context), so the Return read the stack's residue: the
# `my ($k) = @_` before it, and `mk(0)` gave 1 where perl gives "".
round_trips(<<'SRC', 'return-if as the last statement');
sub mk { my ($k) = @_; return "y" if $k > 1 }
print "[", scalar(mk(0)), "]", mk(5), "\n";
SRC

round_trips(<<'SRC', 'return-unless as the last statement');
sub mk { my ($k) = @_; return "n" unless $k > 1 }
print "[", scalar(mk(5)), "]", mk(0), "\n";
SRC

# THE CONDITION ITSELF, not a coincidental 1: `unless $k` falls through to $k.
round_trips(<<'SRC', 'return-unless yields the value of its condition');
sub mk { my ($k) = @_; return "n" unless $k }
print mk("zz"), mk(0), "\n";
SRC

round_trips(<<'SRC', 'in list context');
my %c = (hb => "x");
sub mk { my ($k) = @_; return $c{"h$k"} if exists $c{"h$k"}; }
my @r = (mk("a")); print scalar(@r), "[", (defined $r[0] ? $r[0] : "u"), "]", mk("b"), "\n";
SRC

round_trips(<<'SRC', 'not the last statement: nothing changes');
sub mk { my ($k) = @_; return "y" if $k > 1; "fell" }
print mk(0), mk(5), "\n";
SRC

done_testing;
