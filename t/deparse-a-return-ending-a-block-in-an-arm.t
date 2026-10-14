# ABOUTME: A return ending a multi-statement block nested in an if arm leaves from that
# ABOUTME: block's own branch, so the guard around it is not dropped (chalk's _emit_const_expr).

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


# The emission must also be QUIET: a second `my @e` in one scope is a "masks
# earlier declaration" warning, and the masked variable is the defect.
sub emits_quietly ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}


round_trips(q{sub f { my ($v)=@_; if ($v ne "") { if ($v ne "b") { my $i = $v; return "i$i" } return 2 } 3 } print f("abc"), f("b"), f(""), "\n";},
    'a block of two statements ending in return, in an arm');
round_trips(q{sub f { my ($v)=@_; if ($v =~ /^a/) { if ($v =~ /^a(.*)/) { my $i = $1; return "i$i" } return 2 } 3 } print f("abc"), f("ac"), f("b"), "\n";},
    'the same with a capture read before the return');
round_trips(q{my @r; sub f { my ($v)=@_; for my $k (1..3) { if ($v ne "") { if ($k == 2) { my $i = $v; push @r, $k; return "i$i" } push @r, "x" } } 3 } print f("abc"), f(""), "@r\n";},
    'the same in a loop body, with an effect before the return');

done_testing;
