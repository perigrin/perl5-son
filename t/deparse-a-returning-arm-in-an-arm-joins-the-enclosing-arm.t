# ABOUTME: An If inside an arm, one side returning and the other falling through to the
# ABOUTME: enclosing join, ends where the enclosing walk ends rather than at the exit.

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


# The inner If's two sides meet only at the function's exit: one returns, the
# other leaves the enclosing arm. Taken for the join, the exit pulled the code
# after the enclosing if into the inner false arm and again after it, and the
# read of $e->{l} bound in one copy was unset in the other -- an undeclared
# variable, or a comparison against undef. chalk's Precedence::_scan_multiply.
round_trips(<<'P', 'a returning inner arm beside a fall-through, then a guarded return');
use v5.42.0;
sub nul { 4 }
sub f ($e, $r) {
    if ($r eq "B" || $r eq "A") {
        my $i = nul();
        if ($r eq "A") {
            if (defined $e->{l}) { return "Z" if $e->{l} == 101; }
            return "i";
        }
    }
    return "S" if $r eq "S" && $e->{l} == nul();
    return "n";
}
print f({l => 101}, "A"), f({l => 1}, "A"), f({}, "A"), f({l => 4}, "S"), f({l => 1}, "B"), "\n";
P

round_trips(<<'P', 'the same, ending in an if whose value is the result');
use v5.42.0;
sub look { undef }
sub nul { 4.5 }
sub f ($e, $r) {
    if ($r eq "B" || $r eq "A") {
        my $i = look($r);
        if ($r eq "A") {
            if (defined($e->{l})) { if ($e->{l} == 101) { return "Z"; } }
            return "i";
        }
    }
    if ($r eq "S" && $e->{l} == nul()) { }
}
no warnings;
print f({l => 101}, "A"), f({l => 1}, "A"), f({}, "A"), f({l => 4.5}, "S") // "u", f({l => 1}, "B") // "u", "\n";
P

round_trips(<<'P', 'a value computed after the enclosing if');
use v5.42.0;
sub f ($e, $r) {
    if ($r eq "B" || $r eq "A") {
        my $i = $r x 2;
        if ($r eq "A") { return "Z" if $e > 100; return "i"; }
    }
    my $k = $e + 1;
    return "S$k" if $r eq "S";
    return "n";
}
print f(101, "A"), f(1, "A"), f(4, "S"), f(1, "B"), "\n";
P

done_testing;
