# ABOUTME: A lexical passed to a sprintf that perl folds into a multiconcat is a read:
# ABOUTME: it keeps its binding (a join or loop Phi) instead of an unbound pad access.

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



# A "%s"-ONLY sprintf IS A multiconcat (flagged FAKE), and its pad operand is
# `padsv sM` exactly as it is under sprintf. Read as a fresh PadAccess, the
# value bound at a join or a loop Phi never reached it.
round_trips(<<'SRC', 'a %s sprintf of a value set in a branch');
sub f { my $n = 0; $n = $_[0] if @_; return sprintf "%s", $n }
print f("1.0"), "\n";
SRC

round_trips(<<'SRC', 'a %s sprintf of an arithmetic recurrence');
sub f { my $n = 0; for my $i (1..3) { $n = $n + $i } return sprintf "%s", $n }
print f(), "\n";
SRC

round_trips(<<'SRC', 'a %s sprintf of a value carried by a foreach');
sub f { my $n = 0; for my $x (@_) { $n = $x } return sprintf "%s", $n }
print f("1.0"), "\n";
SRC

round_trips(<<'SRC', 'a decorated %s sprintf of a carried value');
sub f { my $n = 0; for my $x (@_) { $n = $x } return sprintf "<%s>", $n }
print f("1.0"), "\n";
SRC

round_trips(<<'SRC', 'a two-%s sprintf into a lexical');
sub f { my $n = 1; $n = $_[0] if @_; my $r = sprintf "%s-%s", $n, $n; return $r }
print f("a"), "\n";
SRC

done_testing;
