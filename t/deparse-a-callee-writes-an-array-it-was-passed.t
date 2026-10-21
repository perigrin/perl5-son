# ABOUTME: A callee writes through $_[0] into an array element or array it was passed:
# ABOUTME: a later read of the array sees the write, as perl's alias does.

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

# AN ARRAY ELEMENT OR ARRAY PASSED TO A CALL is passed by alias, so the
# callee's `$_[0] = 5` lands in the array. A later list read flattened the
# literal the array was built from: `1 2` for perl's `5 2`.
round_trips(q{sub g { $_[0] = 5 } sub f { my @n = (1,2); g($n[0]); return "@n" } print f(), "\n";},
    'an element passed to a callee that writes it');
round_trips(q{sub g { $_[0] = 5 } sub f { my @n = (1,2); g(@n); return "@n" } print f(), "\n";},
    'an array passed to a callee that writes its first element');
round_trips(q{sub g { $_[1] = 5 } sub f { my @n = (1,2); my $s = "@n"; g(@n); return "$s|@n" } print f(), "\n";},
    'a read before the call is the array before it');
round_trips(q{sub g { $_[0] = 5 } sub f { my @n = (1,2); g($_) for @n; return "@n" } print f(), "\n";},
    'the implicit $_ over an array, passed to a callee that writes it');
round_trips(q{sub g { $_[0] = "x" } sub f { my @n = (1,2); for my $i (0, 1) { g($n[$i]) } return "@n" } print f(), "\n";},
    'an element passed in a loop');
round_trips(q{sub g { $_[0] = 5 } sub f { my %h = (a => 1); g($h{a}); return join ",", %h } print f(), "\n";},
    'a hash element passed to a callee that writes it');

done_testing;
