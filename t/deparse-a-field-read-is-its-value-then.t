# ABOUTME: A read of a scalar class field is the value at that point -- a store after
# ABOUTME: it, by the method or by a call, does not reach a value already read.

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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    if (!$data || $err =~ /skipped/) {
        fail "$name: translates"; diag $err; return;
    }
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

# A FIELD READ HAD NO VERSION. It was one hash-consed FieldAccess, the
# store's target and every read alike, so a read made before a store was
# spelled after it: `my $old = $n; $n = 5; "$old$n"` gave 55 for perl's 15,
# and a method ending `$n = $n + 1` returned the field plus two.
round_trips(<<'SRC', 'a read held across a store');
use v5.42; use experimental 'class';
class K { field $n = 1; method swap { my $old = $n; $n = 5; return "$old$n" } }
print K->new->swap, "\n";
SRC
round_trips(<<'SRC', 'a store whose value is returned');
use v5.42; use experimental 'class';
class K { field $n = 0; method bump { $n = $n + 1 } }
my $k = K->new; my $r = $k->bump; print $r, $k->bump, "\n";
SRC
round_trips(<<'SRC', 'a read held across a method call that stores');
use v5.42; use experimental 'class';
class K { field $n = 1; method set($v) { $n = $v } method run { my $old = $n; $self->set(7); return "$old$n" } }
print K->new->run, "\n";
SRC
round_trips(<<'SRC', 'a read in each arm of a branch around a store');
use v5.42; use experimental 'class';
class K { field $n = 2; method f($c) { my $a = $n; if ($c) { $n = $n * 10 } else { $n = 0 } return "$a:$n" } }
my $k = K->new; print $k->f(1), " ", $k->f(0), "\n";
SRC

# chalk's NodeFactory::make_unique: a guarded lookup, a counted id read
# back after the increment, and a call between the read and its use.
round_trips(<<'SRC', 'an increment, then a read of the field, then a call');
use v5.42; use experimental 'class';
package N { sub new ($c, %a) { bless {%a}, $c } }
my %T = (a => 'N');
class K { field %cache; field $c = 0;
  method mk ($op, %args) { my $class = $T{$op} or die "no $op\n"; $c++; my $id = "${op}#u${c}"; my $node = $class->new(id => $id, %args); $cache{$id} = $node; return $node } }
my $k = K->new; print $k->mk("a")->{id}, " ", $k->mk("a", x => 1)->{id}, "\n";
SRC

done_testing;
