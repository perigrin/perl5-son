# ABOUTME: A join's seed is not taken from an arm whose path passes a merge -- an
# ABOUTME: `or die` Region inside the arm is still inside it, so its value stays there.

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


# THE FUNCTION EXIT'S JOIN is declared at the top of the sub, seeded with the
# input of a predecessor no arm assigns. A predecessor under the else arm
# reached it only through the `or die` merge, and the walk back from it
# stopped at that Region and called it no arm's: the seed `$c{"h$o"}` was
# spelled at the top of the sub, before `$o` -- and in chalk's
# NodeFactory::make, a temporary that did not exist there yet.
round_trips(<<'SRC', 'a guarded return after an or-die, past an early return');
my %c = (hb => "cached");
sub mk { my ($o) = @_; if ($o eq "P") { return "p" } my $k = $o or die "no op\n"; return $c{"h$k"} if exists $c{"h$k"}; "new$k" }
print mk("P"), mk("a"), mk("b"), "\n";
SRC

round_trips(<<'SRC', 'a computed value returned after an or-die');
sub mk { my ($o, $n) = @_; if ($o eq "P") { return "p" } my $k = $o or die "no op\n"; if ($n) { my $v = "$k#$n"; return $v } "plain$k" }
print mk("P"), mk("a", 1), mk("b", 0), "\n";
SRC

# A LOOP IN THE ARM is a single path too: the walk back from past its exit
# stopped at the Loop and gave up the same way.
round_trips(<<'SRC', 'a loop, then an or-die, in the arm');
sub c { 1 }
sub mk { my ($o, $v) = @_; if ($o eq "P") { return "p" } if ($v) { for my $e (@$v) { c($e) } } my $k = $o or die "no\n"; if ($k eq "A") { my $x = "a$k"; return $x } return "m$k" }
print mk("P"), mk("A", [1]), mk("B"), "\n";
SRC

done_testing;
