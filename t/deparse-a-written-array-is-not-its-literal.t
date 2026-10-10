# ABOUTME: A lexical array written by push, an element store or a named sub is read as it now
# ABOUTME: stands: neither a bare `my @a` nor a shared file lexical is read back as its literal.

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


round_trips('my @a; push @a,1,2; my @b=@a; print scalar(@b), "\n";',
    'push into a bare-declared array, then a copy');
round_trips('my @a; $a[0]=1; my @b=@a; print scalar(@b), "\n";',
    'an element store into a bare-declared array, then a copy');
round_trips('my @a; unshift @a,3; push @a,4; my @b=@a; print "@b\n";',
    'unshift and push into a bare-declared array, copied, in list context');
round_trips('sub f { my @a; push @a, @_; my @b = @a; return scalar(@b) } print f(5,6,7), "\n";',
    'push into a bare-declared array inside a sub');
round_trips('my @a; for my $i (1..3) { push @a, $i } my @b=@a; print "@b\n";',
    'push in a loop into a bare-declared array, then a copy');
round_trips('my @F=(1,2); sub f { push @F, 3 } f(); print "@F\n";',
    'a named sub pushing to a file lexical array');
round_trips('my @F=(1,2); sub f { $F[2] = 3 } f(); print scalar(@F), "\n";',
    'a named sub storing an element of a file lexical array, then counted');
round_trips('my @F=(1,2); sub f { push @F, 3 } f(); my @c=@F; print "@c\n";',
    'a named sub pushing to a file lexical array, then a copy');
round_trips(q{my @a=(0); my $i=0; while ($i<3) { push @a, $i; $i++ } print "@a\n";},
    q{push in a loop body, then a list read after the loop});
round_trips(q{my $x=1; my @a=(0); if ($x) { shift @a } my @b=@a; print "@b|\n";},
    q{shift in an arm, then a copy after it});
round_trips(q{sub f { my @p; push @p, "a", "b"; return @p } print f(), "\n";},
    q{push into a bare-declared array, then returned});
round_trips(q{sub f { my @p = (1); shift @p; return @p } my $n = f(); print f(), "|$n\n";},
    q{shift from an array, then returned in list and scalar context});

done_testing;
