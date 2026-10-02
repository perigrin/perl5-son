# ABOUTME: A declared signature is emitted as one -- `sub f($x, $y = 2, @rest)` -- so perl
# ABOUTME: checks the argument count as it did for the source, and a reader sees the parameters.

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
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>&1); unlink $f; return $out;
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

sub round_trips ($src, $name, $spelled = undef) {
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
    like $out, $spelled, "$name: spelled as a signature" if $spelled;
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}


# PARAMETERS WERE SPELLED `$_[N]` UNDER NO SIGNATURE, so the emission took
# any number of arguments where perl checks them: `f(1, 2)` against
# `sub f ($x)` dies "Too many arguments"; emitted, it ran. And chalk, which
# reads lib/ as source, counted no parameters on `method run($input)`.
round_trips(<<'SRC', 'too many arguments to a sub', qr/^sub f\(\$x\) \{/m);
use v5.42;
sub f ($x) { return $x * 2 }
print f(3), "\n";
print eval { f(1, 2); 1 } ? "ran\n" : ($@ =~ /Too many arguments/ ? "too many\n" : "other\n");
SRC

round_trips(<<'SRC', 'too few arguments to a sub');
use v5.42;
sub f ($x, $y) { return $x + $y }
print eval { f(1); 1 } ? "ran\n" : ($@ =~ /Too few arguments/ ? "too few\n" : "other\n");
SRC

round_trips(<<'SRC', 'a method with an unused parameter', qr/^method run\(\$input\) \{/m);
use v5.42; use experimental 'class';
class P { method run($input) { die "Subclass must implement run()\n" } }
print eval { P->new->run(1); 1 } ? "ran\n" : $@;
print eval { P->new->run(); 1 } ? "ran\n" : ($@ =~ /Too few/ ? "too few\n" : "other\n");
SRC

round_trips(<<'SRC', 'an empty signature', qr/^method op\(\) \{/m);
use v5.42; use experimental 'class';
class P { method op() { return 'P' } }
print P->new->op, "\n";
print eval { P->new->op(1); 1 } ? "ran\n" : ($@ =~ /Too many/ ? "too many\n" : "other\n");
SRC

round_trips(<<'SRC', 'defaults of each kind', qr/^sub f\(\$a, \$b = 2, \$c \/\/= 3, \$d \|\|= 4\) \{/m);
use v5.42;
sub f ($a, $b = 2, $c //= 3, $d ||= 4) { return "$a $b $c $d" }
print f(1), "|", f(1, 5, undef, 0), "|", f(1, 5, 6, 7), "\n";
SRC

round_trips(<<'SRC', 'an unused optional parameter');
use v5.42;
sub f ($a, $unused = 9) { return $a }
print f(1), f(2, 3), "\n";
print eval { f(1, 2, 3); 1 } ? "ran\n" : "too many\n";
SRC

round_trips(<<'SRC', 'a slurpy array', qr/^sub f\(\$a, \@rest\) \{/m);
use v5.42;
sub f ($a, @rest) { return "$a:" . scalar(@rest) . ":@rest" }
print f(1), " ", f(1, 2, 3), "\n";
SRC

round_trips(<<'SRC', 'a slurpy hash', qr/^sub f\(\$a, %opts\) \{/m);
use v5.42;
sub f ($a, %opts) { return join(",", $a, map { "$_=$opts{$_}" } sort keys %opts) }
print f(1, y => 2, x => 3), "\n";
SRC

round_trips(<<'SRC', 'a parameter passed on to a call', qr/^sub g\(\$v\) \{/m);
use v5.42;
sub f ($x) { return "f$x" } sub g ($v) { return defined($v) ? f($v) : "u" }
print g(1), g(undef), "\n";
SRC

done_testing;
