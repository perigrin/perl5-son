# ABOUTME: `$h{k}++` and `$a[i]++` yield the element's value from BEFORE the store, and
# ABOUTME: `++$h{k}` the one after -- the read is placed before the write it precedes.

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


# THE OLD VALUE IS A READ AT THE PRE-STORE MEMORY, and the graph said so --
# but nothing placed the read, so the renderer spelled it where it was used,
# after the store: `next if $seen{$id}++` tested the NEW value and skipped
# every node. chalk's Transform::T2::run is exactly that loop, and T2 never
# narrowed a stamp. perl `0 1 2`, emitted `2 2 2`.
round_trips(<<'SRC', 'the seen-hash idiom');
my %s; my $o = ""; for my $x (qw(a a b)) { next if $s{$x}++; $o .= $x } print "$o\n";
SRC

round_trips(<<'SRC', 'a hash element post-increment, used');
my %s; my $v = $s{a}++; my $w = $s{a}++; print "$v $w $s{a}\n";
SRC

round_trips(<<'SRC', 'an array element post-increment, used');
my @a = (5); my $v = $a[0]++; print "$v $a[0]\n";
SRC

round_trips(<<'SRC', 'a hash element pre-increment, used');
my %s; my $v = ++$s{a}; my $w = ++$s{a}; print "$v $w $s{a}\n";
SRC

round_trips(<<'SRC', 'an element post-decrement, used');
my %n = (a => 2); my $v = $n{a}--; my $w = $n{a}--; print "$v $w $n{a}\n";
SRC

# A POST-INCREMENT OF UNDEF YIELDS 0, not undef -- perl's pp_postinc sets its
# result to 0 when the old value is not defined. A post-DECREMENT does not,
# and a string comes back unchanged. Every form was missing it.
round_trips(<<'SRC', 'post-increment of an undefined scalar, element and field');
use v5.42; use experimental 'class';
class C { field $n; method b { my $v = $n++; return defined $v ? "[$v]" : "u" } }
my ($x, $y, %h); my $p = $x++; my $q = $y--; my $r = $h{k}++; my $s = "aa"; my $t = $s++;
sub show { my $v = shift; return defined $v ? "[$v]" : "u" }
print show($p), show($q), show($r), show($t), C->new->b, "\n";
SRC

done_testing;
