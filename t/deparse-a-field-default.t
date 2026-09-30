# ABOUTME: A class field's default survives the round trip -- an aggregate's list of
# ABOUTME: constants is emitted; a default the wire cannot carry refuses by name.

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

# AN AGGREGATE FIELD'S LIST WAS DROPPED. `field %m = (a => 1)` compiles its
# default to a list, which the default extractor did not recognise, so the
# emission declared `field %m;` and every read found it empty.
round_trips(<<'SRC', 'a hash field with a list default');
use v5.42; use experimental 'class';
class K { field %m = (a => 1, b => 2); method all { join ",", map { "$_=$m{$_}" } sort keys %m } }
print K->new->all, "\n";
SRC

round_trips(<<'SRC', 'an array field with a list default');
use v5.42; use experimental 'class';
class K { field @l = (3, 4, 5); method n { scalar @l } method last_ { $l[-1] } }
my $o = K->new; print $o->n, $o->last_, "\n";
SRC

round_trips(<<'SRC', 'a scalar default, and a ref default that rendered as a list');
use v5.42; use experimental 'class';
class K { field $n = 3; field $r = [1, 2]; method all { $n . scalar(@$r) } }
print K->new->all, "\n";
SRC

# A DEFAULT THE WIRE CANNOT CARRY -- a computed one -- was dropped just as
# silently. It refuses now, naming the field, rather than emitting a class
# whose field starts undef.
{
    my $src = <<'SRC';
use v5.42; use experimental 'class';
class K { field $t = time; method has { defined $t ? "y" : "n" } }
print K->new->has, "\n";
SRC
    my $data = graph_of($src);
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    ok !defined $out, 'a computed field default refuses';
    like $d->gap // '', qr/GAP: the default of field `\$t` in class K/,
        '... naming the field and its class';
}

done_testing;
