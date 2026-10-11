# ABOUTME: An element read copied out before a store to that element keeps the old value
# ABOUTME: in the emission: the read is bound at its memory version, not spelled at its use.

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


round_trips('my @a=(4); my $z = $a[0]; $a[0] = 1; print "$z $a[0]\n";',
    'an array element copied, then stored');
round_trips('sub f { my @a=(4); my $z = $a[0]; $a[0] = 1; return "$z $a[0]" } print f(), "\n";',
    'the same inside a sub');
round_trips('my %h=(k => 4); my $z = $h{k}; $h{k} = 1; print "$z $h{k}\n";',
    'a hash element copied, then stored');
round_trips('sub f { my $r = [4]; my $z = $r->[0]; $r->[0] = 1; return "$z $r->[0]" } print f(), "\n";',
    'an element through a reference copied, then stored');
round_trips('my @a=(1,2); my $s = $a[0]; sub g { $_[0][0] += 5 } g(\@a); print "$s $a[0]\n";',
    'an element copied, then changed by a call through a reference');
round_trips('my @a=(4); $a[0] = 1; my $z = $a[0]; print "$z\n";',
    'a read after the store sees the stored value');

round_trips(q{sub g { return (4, 5) } sub f { my @c = g(); my $z = $c[0]; $c[0] = 1; return "$z $c[0]" } print f(), "\n";},
    q{an element of an array filled by a call, copied, then stored});
round_trips(q{my @a=(4); my $z = $a[0]; sub h { 1 } h(); $a[0] = 1; print "$z $a[0]\n";},
    q{a call between the copy and the store});


# A READ USED ONLY INSIDE AN ARM is not bound ahead of it: perl's
# comp/our.t reads $caller[1] in an else that declares @caller.
round_trips(q{my $t = 0; sub is { my ($g) = @_; $t = $t + 1; if ($g) { print "ok $t\n"; return 1 } my @c = (7, 8, 9); print "not ok $t at $c[1] $c[2]\n"; return } is(1); is(0);},
    q{an element read only in the arm that declares its array});
round_trips(q{my @a=(1); my $c=1; if ($c) { my $y = $a[0]; $a[0] = 7; print "$y\n" } print "$a[0]\n";},
    q{a read and its store inside one arm});

done_testing;
