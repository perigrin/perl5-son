# ABOUTME: An if-arm whose every path ends in `next` -- one through a nested
# ABOUTME: `next if`, one after an inner loop -- is a `next`, not a join.

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

# EVERY PATH OF THE ARM GOES ROUND. The nested `if (...) { ...; next }` has no
# merge of its own -- one side goes round, the other runs an inner loop and
# then goes round too -- and the latch test stopped at it, so the latch was
# taken as the If's join and its Phi had no predecessors (chalk's
# LLVM::Context::_compile_regex_pattern).
round_trips(<<'SRC', 'an arm whose nested next-if and inner loop both go round');
sub f {
    my @c = @_;
    my @o;
    my $i = 0;
    while ($i <= $#c) {
        my $x = $c[$i];
        if ($x eq 'b') {
            if ($c[$i+1] eq 'w') {
                $i += 2;
                next;
            }
            my $j = $i + 1;
            while ($j <= $#c) {
                $j++;
            }
            $i = $j;
            next;
        }
        if ($x eq '.') {
            $i++;
            next;
        }
        push @o, $x;
        $i++;
    }
    return "@o";
}
print f(qw(a b w . c b x y)), "\n";
print f(qw(a . b x)), "\n";
SRC

done_testing;
