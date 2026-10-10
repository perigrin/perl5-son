# ABOUTME: A foreach over an aggregate with the implicit $_ iterator writes through the
# ABOUTME: alias: `$_ OP= x`, `++$_` and `$_--` read the element and store back into it.

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


round_trips('my @a=(3,4); for (@a) { $_ *= 2 } print "@a\n";',
    'an op= through the implicit iterator of a lexical array');
round_trips('sub f { my @a=(3,4); for (@a) { $_ *= 2 } return "@a" } print f(), "\n";',
    'the same inside a sub');
round_trips('our @g=(3,4); for (@g) { $_ **= 2 } print "@g\n";',
    'an op= through the implicit iterator of a package array');
round_trips('my $r=[3,4]; for (@$r) { $_ += 1 } print "@$r\n";',
    'an op= through the implicit iterator of an array reference');
round_trips('my @a=(3,4); $_ -= 1 for @a; print "@a\n";',
    'a postfix foreach');
round_trips('my @a=(3,4); for (@a) { ++$_ } print "@a\n";',
    'a pre-increment through the implicit iterator');
round_trips('my @a=(3,4); for (@a) { $_-- } print "@a\n";',
    'a post-decrement through the implicit iterator');
round_trips('my @a=(3,4); for (@a) { $_ .= "x" } print "@a\n";',
    'a concatenating op= through the implicit iterator');

done_testing;
