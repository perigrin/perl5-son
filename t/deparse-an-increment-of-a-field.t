# ABOUTME: `$field++`, `++$field`, `--$field` store into the class field and yield the
# ABOUTME: old or the new value as perl does -- not an arithmetic node bound to nothing.

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

# THE INCREMENT HANDLER HAD FIVE WRITE FORMS AND NO FIELD. A field's lvalue
# padsv is a FieldAccess, which matched none, so the Add was built and
# dropped: the counter never counted. chalk's CoreItemIndex `my $id =
# $count++` gave every item id 0 -- 150 of chalk's test files failed
# against the emitted lib/.
round_trips(<<'SRC', 'a post-increment of a field, its value used');
use v5.42; use experimental 'class';
class K { field $c = 0; method n { my $i = $c++; return $i } }
my $k = K->new; print $k->n, $k->n, $k->n, "\n";
SRC

round_trips(<<'SRC', 'a pre-increment of a field');
use v5.42; use experimental 'class';
class K { field $c = 0; method n { return ++$c } }
my $k = K->new; print $k->n, $k->n, "\n";
SRC

round_trips(<<'SRC', 'a void increment and a decrement');
use v5.42; use experimental 'class';
class K { field $c = 5; method up { $c++; return $c } method down { $c--; return $c } }
my $k = K->new; print $k->up, $k->down, $k->down, "\n";
SRC

round_trips(<<'SRC', 'the register shape: a guarded return, then a counted id');
use v5.42; use experimental 'class';
class K { field %ids; field $count = 0;
  method register($k) { return $ids{$k} if exists $ids{$k}; my $id = $count++; $ids{$k} = $id; return $id } }
my $o = K->new; print join(",", map { $o->register($_) } qw(a b a c)), "\n";
SRC

done_testing;
