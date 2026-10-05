# ABOUTME: A call to a main:: sub from a method keeps its package -- the method is
# ABOUTME: emitted inside its class block, where a bare name means the class's own sub.

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


# THE RENDERER SPELLS main::c AS `c`, which is right at file scope and wrong
# inside `class F { }`: there `c()` is F::c, and the emission died
# "Undefined subroutine &F::c".
round_trips(<<'SRC', 'a main:: call from a method');
use v5.42.0; use experimental "class";
sub c { "c" }
class F { method f { main::c() } }
print F->new->f, "\n";
SRC

round_trips(<<'SRC', 'a reference to a main:: sub from a method');
use v5.42.0; use experimental "class";
sub c { "rc" }
class F { method f { my $r = \&main::c; $r->() } }
print F->new->f, "\n";
SRC

round_trips(<<'SRC', 'a main:: call from a package sub');
sub c { "c" }
package P { sub f { main::c() } }
print P::f(), "\n";
SRC

# A CODE REFERENCE CARRIED ONLY THE SUB'S SHORT NAME: `\&Q::c` arrived as `c`
# and the emission called main::c, which does not exist.
round_trips(<<'SRC', 'a reference to a sub in another package');
package Q { sub c { "q" } }
package P { sub f { my $r = \&Q::c; $r->() } }
print P::f(), "\n";
SRC

done_testing;
