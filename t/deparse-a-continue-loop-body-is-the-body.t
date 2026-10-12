# ABOUTME: A loop with a continue block or a C-style step wraps its body in a block;
# ABOUTME: an if in that block is a guard on the body, never the loop's own condition.

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


round_trips(<<'SRC', 'a C-style for: an if block first in the body');
sub f { my @o; for (my $i = 0; $i < 3; $i++) { if ($i == 1) { push @o, "s" } push @o, $i } return join ",", @o }
print f(), "\n";
SRC

round_trips(<<'SRC', 'a C-style for: an if block that nexts to the step');
sub f { my @o; for (my $i = 0; $i < 3; $i++) { if ($i == 1) { push @o, "s"; next } push @o, $i } return join ",", @o }
print f(), "\n";
SRC

round_trips(<<'SRC', 'a C-style for: a compound if that moves the counter and nexts');
sub f { my @p = @_; my @o; for (my $i = 0; $i < @p; $i += 2) { my $k = $p[$i]; if (defined $k && $k =~ /^%(\w+)$/) { push @o, "s$1"; $i--; next } push @o, "$k=$p[$i+1]" } return join ",", @o }
print f("a", 1, "%x", "b", 2), "\n";
SRC

round_trips(<<'SRC', 'a while with a continue block: an if block in the body');
sub f { my @o; my $i = 0; while ($i < 3) { if ($i == 1) { push @o, "s" } push @o, $i } continue { $i++ } return join ",", @o }
print f(), "\n";
SRC

round_trips(<<'SRC', 'a C-style for: a guarded store after a statement');
sub f { my $s = 0; for (my $i = 0; $i < 5; $i++) { my $x = $i * 2; $s += $x if $x > 2 } return $s }
print f(), "\n";
SRC

done_testing;
