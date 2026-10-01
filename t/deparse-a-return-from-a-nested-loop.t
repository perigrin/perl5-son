# ABOUTME: A guarded `return` in a nested loop leaves both loops and the sub -- and the
# ABOUTME: probe that asks whether a body writes its iterator records nothing real.

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

# THE ITERATOR-WRITE PROBE WALKED THE BODY WITHOUT SAYING IT WAS A SCOUT,
# so the inner loop's guarded return recorded a function exit built from
# probe nodes: a second, scout-only inner loop leaked into the graph, and the
# renderer refused "a control node with 2 successors" (chalk's
# Grammar/Rule.pm is_terminal_rule, among 15 modules).
round_trips(<<'SRC', 'a guarded return in an inner foreach');
sub f { for my $alt (@_) { for my $s (@$alt) { return 0 unless $s } } return 1 }
print f([1, 1], [1]), f([1], [0]), f(), "\n";
SRC

round_trips(<<'SRC', 'a return of a value from an inner loop');
sub find { my $t = shift; for my $row (@_) { for my $x (@$row) { return "$x!" if $x == $t } } return "none" }
print find(3, [1, 2], [3, 4]), find(9, [1]), "\n";
SRC

done_testing;
