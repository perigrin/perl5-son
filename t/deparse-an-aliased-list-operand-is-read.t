# ABOUTME: A scalar named in the list a map, grep or foreach walks is read for its value when
# ABOUTME: nothing writes the alias: perl flags it OPf_MOD, and the slot alone lost the value.

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


# EACH ELEMENT IS ALIASED -- to `$_`, or to the loop variable -- so perl flags
# the operand OPf_MOD, as it does a call argument. Taken for an lvalue, the
# padsv pushed the variable's SLOT, which held nothing the graph had bound:
# `map { "[$_]" } $p, $q` printed `[],[]`. `time() * 0` keeps the values from
# folding away.
round_trips(<<'SRC', 'a map over named scalars');
my $p = 1 + time() * 0; my $q = 2 + time() * 0; print join(",", map { "[$_]" } $p, $q), "\n";
SRC

round_trips(<<'SRC', 'a foreach over named scalars');
my $p = 1 + time() * 0; my $q = 2 + time() * 0; my $o = ""; for my $v ($p, $q) { $o .= "[$v]" } print "$o\n";
SRC

round_trips(<<'SRC', 'a grep over named scalars');
my $p = 1 + time() * 0; my $q = 2 + time() * 0; print join(",", grep { $_ > 1 } $p, $q), "\n";
SRC

round_trips(<<'SRC', 'an array and a scalar in one map list');
my @l = (1, 2); my $q = 3 + time() * 0; print join(",", map { $_ * 2 } @l, $q), "\n";
SRC

# WRITING THROUGH THE ALIAS is still refused, and must not turn into a
# silent read: the variable would keep its old value.
{
    my $data = graph_of('my $p = 1 + time() * 0; my $q = 2 + time() * 0; for my $v ($p, $q) { $v *= 2 } print "$p $q\n";');
    my $d = SoN::Deparse->new;
    my $out = $data ? $d->render($data) : undef;
    ok !defined $out, 'a write through a foreach alias refuses';
    like $d->gap // '', qr/element store into an anonymous container/, '... by name';
}

done_testing;
