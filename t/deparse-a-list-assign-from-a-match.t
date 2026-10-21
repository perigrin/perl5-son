# ABOUTME: `my ($a, $b) = $s =~ /(..)(..)/` takes the match's captures, or nothing
# ABOUTME: when it fails: a list-context match has no fixed positions.

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

# A MATCH IN LIST CONTEXT IS A LIST of its captures, so the targets keep their
# own slots and perl distributes the list -- bound positionally, $c took the
# match's truth and $s undef (`1 ` for `A b`; chalk's
# IR::Analysis::_attach_call_targets).
round_trips(q{my $n = "A::b"; my ($c, $s) = $n =~ /^(.*)::(.*)$/; print "$c $s\n";},
    'two captures into two new scalars');
round_trips(q{sub f { my ($n) = @_; my ($c, $s) = ($n // "") =~ /^(.*)::([^:]+)$/; return defined $c ? "$c $s" : "none" } print f("A::b"), "|", f("q"), "\n";},
    'a failed match leaves them undef');
round_trips(q{sub f { my ($v) = @_; my ($a, $b); ($a, $b) = $v =~ /(\d)(\d)/; return ($a // "u") . ($b // "u") } print f("x12"), f("x"), "\n";},
    'into scalars declared earlier');
round_trips(q{my ($w) = "abc" =~ /b/; my ($x) = "abc" =~ /z/; print $w, defined $x ? "d" : "u", "\n";},
    'a match without groups yields 1, or nothing');

done_testing;
