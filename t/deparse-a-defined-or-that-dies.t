# ABOUTME: A `//` whose fallback dies -- `my $c = shift // die "..."` -- dies only when
# ABOUTME: the left side is undefined, as perl's short-circuit says.

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


# The fallback was walked on the operator's own control: its Unwind hung off
# the shift beside the Return, with no If to choose between them -- "a
# control node with 2 successors". chalk's LLVM::Context::_lower_call_new
# names its class with `$node->class_name // die ...`.
round_trips(<<'P', 'a value // die');
sub f { my $c = shift // die "none\n"; return $c }
print f(1), f(0), eval { f() } // "E", $@;
P

round_trips(<<'P', 'an element // die, read after');
sub f { my $c = $_[0] // die "none: $_[1]\n"; return $c + 1 }
print f(1, "a"), eval { f(undef, "b") } // "E", $@;
P

round_trips(<<'P', 'a void // die');
sub f { my $c = shift; $c // die "none\n"; return $c }
print f(1), eval { f() } // "E", $@;
P

round_trips(<<'P', 'a // die in a loop');
sub f { my $s = 0; for my $x (@_) { my $v = $x->{v} // die "no v\n"; $s += $v } return $s }
print f({v => 1}, {v => 2}), eval { f({v => 1}, {}) } // "E", $@;
P

done_testing;
