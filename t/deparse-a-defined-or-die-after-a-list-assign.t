# ABOUTME: `E // die` after a void list assign: the die arm pushes no value, so
# ABOUTME: the fallback is not the list assign's residue left on the stack.

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

# THE FALLBACK IS WHAT THE ARM PUSHED. A `die` pushes nothing, and the pop took
# the stack's residue -- the list assign before it -- as the value, while the
# merge made a Phi of the residue beneath (chalk's
# LLVM::Context::_lower_str_compare, `($l, $r) = ($lp, $rp); my $n = $ll // die`).
round_trips(q{sub p { ("p$_[0]", length $_[0]) } sub f { my ($a) = @_; my ($ap, $al) = p($a); ($a) = ($ap); my $l = $al // die "no"; return "$a $l" } print f("x"), "\n";},
    'a defined-or die after a list assign into an existing scalar');
round_trips(q{sub p { ("p$_[0]", length $_[0]) } sub f { my ($a, $b) = @_; my ($ap, $al) = p($a); my ($bp, $bl) = p($b); ($a, $b) = ($ap, $bp); my $l = $al // die "no ($a)"; return "$a $b $l" } print f("x", "yy"), "\n";},
    'and the die message reads a target');

done_testing;
