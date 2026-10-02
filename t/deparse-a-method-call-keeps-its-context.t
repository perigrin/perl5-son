# ABOUTME: A method call carries the context perl compiled it in, as a direct call does:
# ABOUTME: a list-context call to a method returning an array yields the elements, not a count.

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


# ONLY A DIRECT CALL CARRIED `want`. A method call fell back to its stamp,
# and `return @p` infers no List stamp, so the binding took a scalar: `my
# $eff4 = $self->parts()`, the count. chalk's Node::content_hash is
# join('|', $self->operation(), $self->_serialize_inputs()) -- every hash
# collided, and hash-consing merged different nodes. perl x|a|b, emitted x|2.
round_trips(<<'SRC', 'a method returning an array, in a list');
use v5.42; use experimental 'class';
class N { method parts() { my @p; push @p, "a", "b"; return @p }
          method h() { return join("|", "x", $self->parts()) } }
print N->new->h, "\n";
SRC

round_trips(<<'SRC', 'the same method in scalar context');
use v5.42; use experimental 'class';
class N { method parts() { my @p; push @p, "a", "b"; return @p }
          method n() { my $c = $self->parts(); return $c } }
print N->new->n, "\n";
SRC

round_trips(<<'SRC', 'a class method returning an array, in a list');
use v5.42; use experimental 'class';
class N { method parts() { my @p; push @p, "a", "b"; return @p } }
my @got = N->new->parts(); print scalar(@got), ":@got\n";
SRC

round_trips(<<'SRC', 'a dynamic method returning an array, in a list');
use v5.42; use experimental 'class';
class N { method parts() { my @p; push @p, "a", "b"; return @p }
          method h($m) { return join("|", "x", $self->$m()) } }
print N->new->h("parts"), "\n";
SRC

# THE CALLER'S CONTEXT USED TO HIDE THIS: a field aggregate's first read in
# scalar context gave the aggregate, not its count, and the scalar-bound
# call counted it anyway. Bound by `want`, a list caller took the elements.
round_trips(<<'SRC', 'a method counting a field array, called in a list');
use v5.42; use experimental 'class';
class K { field @l = (3, 4, 5);
          method n { scalar @l } method p { return scalar(@l) } method q { return @l ? "y" : "n" } }
my $o = K->new; my @a = ($o->n, $o->p, $o->q); print "@a\n";
SRC

round_trips(<<'SRC', 'a method counting a field hash, called in a list');
use v5.42; use experimental 'class';
class K { field %h = (a => 1, b => 2); method n { scalar %h } }
my @a = (K->new->n); print "@a\n";
SRC

# A LIST BUILTIN RETURNED TAKES ITS CONTEXT FROM THE CALLER: its op says
# nothing (want 0), and reading that as scalar stamped `values %c` a count
# -- `return scalar(values(%c))`, 1 element where perl gives 2. chalk's
# Chalk::MOP::classes is `return values %classes`, and every test that
# walked the MOP got a number where it wanted classes.
round_trips(<<'SRC', 'values returned to a list caller');
use v5.42; use experimental 'class';
class M { field %c; method add($k) { $c{$k} = 1; return } method all() { return values %c } }
my $m = M->new; $m->add("a"); $m->add("b"); my @l = $m->all; my $n = $m->all; print scalar(@l), " $n\n";
SRC

round_trips(<<'SRC', 'keys and values returned, in both contexts');
use v5.42;
sub k { my %c = (a => 1, b => 2); return keys %c } sub v { my %c = (a => 1); values %c }
my @k = k(); my $k = k(); my @v = v(); my $v = v(); print scalar(@k), " $k ", scalar(@v), " $v\n";
SRC

done_testing;
