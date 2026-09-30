# ABOUTME: An element of a class's field aggregate -- `$m{$k}`, `$a[$i]` -- is spelled
# ABOUTME: as an element of the field, for a read, an exists and a delete alike.

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

# A FieldAccess carries no sigil and an Unknown stamp, so the element
# fell through to the reference branch: `(%m)->[$k]`, "Can't use a hash as
# a reference" (chalk's CoreItemIndex.pm).
round_trips(<<'SRC', 'a field hash element read');
use v5.42; use experimental 'class';
class K { field %m; method set($k) { $m{$k} = 1 } method get($k) { $m{$k} // "none" } }
my $o = K->new; $o->set("a"); print $o->get("a"), $o->get("b"), "\n";
SRC

round_trips(<<'SRC', 'exists on a field hash element');
use v5.42; use experimental 'class';
class K { field %m; method set($k) { $m{$k} = 1 } method has($k) { exists $m{$k} ? "y" : "n" } }
my $o = K->new; $o->set("a"); print $o->has("a"), $o->has("b"), "\n";
SRC

round_trips(<<'SRC', 'a field array element read and exists');
use v5.42; use experimental 'class';
class K { field @a; method set($i) { $a[$i] = 7 } method has($i) { exists $a[$i] ? $a[$i] : "n" } }
my $o = K->new; $o->set(1); print $o->has(1), $o->has(0), "\n";
SRC

round_trips(<<'SRC', 'delete from a field hash');
use v5.42; use experimental 'class';
class K { field %m; method set($k) { $m{$k} = 1 } method drop($k) { delete $m{$k}; return join ",", sort keys %m } }
my $o = K->new; $o->set("a"); $o->set("b"); print $o->drop("a"), "\n";
SRC

done_testing;
