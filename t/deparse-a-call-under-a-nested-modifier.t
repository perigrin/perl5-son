# ABOUTME: A call in a statement modifier nested in an if/else arm runs only when its guard
# ABOUTME: holds -- void or valued, `helper() if $c` or `$r = f() if $c` -- once, not twice.

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


# REFUSED "a void call inside a nested one-armed branch": once, such a call
# was pinned on the arm's own control and emitted on both paths (`helped`
# twice). The handler now builds an If for it, as it does for a print -- and
# for a call whose VALUE is used, which advances control the same way.
# 33 of chalk's graphs refused here.
round_trips(<<'SRC', 'a void call under a nested modifier');
my $n = 0; sub helper { $n++; print "helped\n" }
sub f { my ($x, $y) = @_; if ($x > 3) { helper() if $y > 3 } return $n }
print f(5, 5), f(5, 1), f(1, 5), "\n";
SRC

round_trips(<<'SRC', 'a valued call under a nested modifier');
my $n = 0; sub g { $n++; return $_[0] * 2 }
sub f { my ($x, $y) = @_; my $r = 0; if ($x > 3) { $r = g($y) if $y > 3 } return "$r:$n" }
print f(5, 5), " ", f(5, 1), " ", f(1, 5), "\n";
SRC

round_trips(<<'SRC', 'a method call under a nested unless');
package C { sub new { bless {}, shift } sub hit { $_[0]{n}++ } sub n { $_[0]{n} // 0 } }
sub f { my ($o, $x) = @_; if ($x) { $o->hit unless $x > 5 } return $o->n }
my $o = C->new; print f($o, 1), f($o, 9), f($o, 0), "\n";
SRC

done_testing;
