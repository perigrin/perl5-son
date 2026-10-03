# ABOUTME: A value `&&` / `||` / `//` in a loop body whose right side calls runs that call
# ABOUTME: only when the left side lets it -- a branch with a merged value, not a refusal.

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


# THE LOOP BODY'S VALUE short-circuit took only pure arms; an arm with a call
# fell to the loop-condition handler, which refused "nested and/or inside a
# loop body" -- 37 of chalk's graphs, `next unless $n->can(...) && ...` among
# them. The call is counted, so running it unconditionally would show.
round_trips(<<'SRC', 'a three-way && with calls guarding next');
my $n = 0; sub g { $n++; return $_[0] }
sub f { my $o = ""; for my $x (@_) { next unless g($x) && g($x) > 1 && g($x) < 9; $o .= $x } return "$o:$n" }
print f(1, 2, 3, 9), "\n";
SRC

round_trips(<<'SRC', 'a value && with a call, in a foreach');
my $n = 0; sub g { $n++; return $_[0] }
sub f { my $o = ""; for my $x (@_) { my $v = $x && g($x) && g($x) > 1; $o .= $v ? "y" : "n" } return "$o:$n" }
print f(0, 2, 1), "\n";
SRC

round_trips(<<'SRC', 'a value || with a call, in a while');
my $n = 0; sub g { $n++; return 7 }
sub f { my @q = @_; my $o = ""; while (@q) { my $x = shift @q; my $v = $x || g(); $o .= $v } return "$o:$n" }
print f(0, 2, 0), "\n";
SRC

round_trips(<<'SRC', 'a value // with a call, in a foreach');
my $n = 0; sub g { $n++; return 7 }
sub f { my $o = ""; for my $x (@_) { my $v = $x // g(); $o .= $v } return "$o:$n" }
print f(undef, 2, undef), "\n";
SRC

done_testing;
