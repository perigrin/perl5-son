# ABOUTME: A `return` inside a loop body leaves the loop and the sub: an exit
# ABOUTME: edge from inside the body to the function's single Return.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

# A TIME LIMIT, as for every loop test: a wrong lowering can spin.
sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; diag producer_stderr(); return;
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

# THE RETURN WAS DROPPED. After `next if`, the rest of the body is walked as
# an arm with no exit list, so the `return` popped its value and built
# nothing: `pick(50)` fell out of the loop and returned "none" where perl
# returns "big-2". Nothing refused. Corpus 008.
round_trips(<<'SRC', 'a return after a next if, in a foreach');
use v5.36;
sub pick ($n) {
    for my $i (1 .. 2) {
        next if $i == 1;
        return "big-" . $i;
    }
    return "none";
}
print pick(50), "\n";
SRC

# A RETURN IN A LOOP BODY REFUSED ("function exit inside a loop body").
round_trips(<<'SRC', 'return X if C in a foreach');
sub p2 { for my $i (1..3) { return "r$i" if $i == 2 } return "none" }
print p2(), " ", "\n";
SRC

round_trips(<<'SRC', 'an unconditional return in a loop body');
sub p3 { my @s; for my $i (1..3) { push @s, $i; return "r$i" } return "none" }
print p3(), "\n";
SRC

round_trips(<<'SRC', 'a return that is not taken falls out of the loop');
sub p4 { my $n = shift; my $t = 0;
         for my $i (1..3) { $t += $i; return "early" if $t > $n }
         return "t=$t" }
print p4(100), " ", p4(2), "\n";
SRC

round_trips(<<'SRC', 'a return in a while body after a plain next if');
sub p5 { my $i = 0;
         while ($i < 5) { $i++; next if $i < 3; print "at$i "; return $i * 10 }
         return -1 }
print p5(), "\n";
SRC

done_testing;
