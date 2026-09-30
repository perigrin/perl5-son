# ABOUTME: An element store inside a nested one-armed branch -- `if (A) { $h{k} = v
# ABOUTME: if B }` -- runs only when both guards hold, and the read after sees it.

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

# THE MEASURED CASE the refusal names: routed through the control-only
# build, the store was dropped and both polarities printed the same thing.
for my $args ([1, 1], [1, 0], [0, 1]) {
    round_trips(<<"SRC", "a nested store, guards @$args");
sub f { my (\$c, \$d) = \@_; my \@a = (1); if (\$c) { \$a[0] = 9 if \$d } \$a[0] }
print f($args->[0], $args->[1]), "\\n";
SRC
    round_trips(<<"SRC", "a nested unless-store into a hash, guards @$args");
sub f { my (\$c, \$d) = \@_; my \%h = (k => 1); if (\$c) { \$h{k} = 9 unless \$d } \$h{k} }
print f($args->[0], $args->[1]), "\\n";
SRC
    round_trips(<<"SRC", "a nested block if, guards @$args");
sub f { my (\$c, \$d) = \@_; my \@a = (1, 2, 3); if (\$c) { if (\$d) { \$a[0] = 9 } } \$a[0] }
print f($args->[0], $args->[1]), "\\n";
SRC
}

done_testing;
