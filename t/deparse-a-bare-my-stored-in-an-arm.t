# ABOUTME: A lexical declared bare and first stored in a branch arm stays in scope after
# ABOUTME: the branch: its `my` is not the store inside the arm.

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


# `my $so;` LEAVES NO NODE OF ITS OWN when the slot is demoted (passed to a
# sub), so the renderer took the first store as the declaration -- and the
# first store was inside the `if`: `if (...) { my $so = "x" } load($so)`,
# undeclared at the call. chalk's Bootstrap::Runtime finds chalk.so so.
round_trips(<<'SRC', 'a bare my, stored in an arm, passed to a sub');
sub load { "L:" . ($_[0] // "u") }
my $so; if (time) { $so = "x"; } print load($so), "\n";
SRC

round_trips(<<'SRC', 'in a sub, with an else');
sub load { "L:" . ($_[0] // "u") }
sub f { my ($p) = @_; my $so; if ($p) { $so = "x"; } else { $so = "y"; } return load($so) }
print f(1), f(0), "\n";
SRC

round_trips(<<'SRC', 'one name declared in two sibling arms');
sub show { "[$_[0]]" }
sub f { my ($p) = @_; my $out = ""; if ($p) { my $v = "a"; $out .= show($v) } else { my $v = "b"; $out .= show($v) } return $out }
print f(1), f(0), "\n";
SRC

done_testing;
