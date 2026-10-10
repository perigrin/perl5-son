# ABOUTME: A file lexical shared with a named sub, read at the sub's entry and then stored,
# ABOUTME: keeps the value it had on entry: $n++ returns the old value, a copy is not clobbered.

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


round_trips('my $n=0; sub f { my $x = $n++; return $x } my $a=f(); my $b=f(); print "$a $b $n\n";',
    'a post-increment copied out of a shared lexical');
round_trips('my $n=0; sub f { return $n++ } my $a=f(); my $b=f(); print "$a $b $n\n";',
    'a post-increment returned directly');
round_trips('my $n=0; sub f { my $x = $n--; return $x } my $a=f(); my $b=f(); print "$a $b $n\n";',
    'a post-decrement');
round_trips('my $n=5; sub f { my $x = $n; $n = 9; return $x } my $a=f(); print "$a $n\n";',
    'a plain copy, then a store');
round_trips('my $n=0; sub f { my $x = $n++; my $y = $n++; return "$x$y" } print f(), " $n\n";',
    'two post-increments in one sub');
round_trips('my $n=0; sub f { my $x = $n++ + 10; return $x } print f(), " ", f(), "\n";',
    'a post-increment inside an expression, the sub in list context');
round_trips('our $n=0; sub f { my $x = $n++; return $x } my $a=f(); my $b=f(); print "$a $b $n\n";',
    'the package-scalar form');
round_trips('my $n=0; my $x = $n++; print "$x $n\n";',
    'the top-level form');
round_trips('sub f { my $n = 0; my $x = $n++; return "$x $n" } print f(), "\n";',
    'a lexical of the sub itself');
round_trips('my $n=0; sub f { if ($_[0]) { return $n++ } return -1 } print f(1), f(0), f(1), " $n\n";',
    'a post-increment in a branch arm');
round_trips('my $n=0; sub f { $n = 5; my $x; if ($_[0]) { $x = $n; $n = 1 } else { $x = 2 } return $x } print f(1), f(0), " $n\n";',
    'a copy then a store, both in a branch arm, after an earlier store');
round_trips('my @a; my $n=0; sub f { my $x = $n; $n = 4; push @a, $x; return $x } f(); f(); print "@a $n\n";',
    'the copy pushed after the store');
round_trips('our $n=0; sub f { for (1..3) { $n++ } return $n } print f(), " $n\n";',
    'a void post-increment in a loop in a sub');
round_trips('our $n; my @r; for (1..3) { push @r, $n++ } print "@r $n\n";',
    'a post-increment in a top-level loop, which carries it');

# IN A LOOP INSIDE A SUB, the scalar has no header Phi: the read names the
# entry memory version on every pass. A use after the body's store is refused.
sub refuses ($src, $name) {
    my $data = graph_of($src);
    ok $data, "$name: translates" or return;
    my $d = SoN::Deparse->new;
    is $d->render($data), undef, "$name: does not render";
    like $d->gap // '', qr/is read at entry and stored in a loop with no carried value/,
        "$name: the refusal names the uncarried read";
}
refuses('my $n=0; sub f { my @r; for (1..3) { push @r, $n++ } return "@r" } print f(), " $n\n";',
    'a shared lexical post-incremented in a loop, value used');
refuses('our $n=0; sub f { my @r; for (1..3) { push @r, $n++ } return "@r" } print f(), " $n\n";',
    'the package-scalar form');
refuses('my $n=0; sub f { my $s=""; for (1..3) { $s .= $n; $n += 2 } return $s } print f(), " $n\n";',
    'a read before a compound store in a loop');

done_testing;
