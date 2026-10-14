# ABOUTME: A loop-carried value whose back-edge has no stamp round trips: the scout
# ABOUTME: decides the header Phi's stamp before the body walk, so nothing is unstamped.

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


# Chalk::Bootstrap::Bindings::_remove_trivial_phi: `my $v;` then a plain
# overwrite with an element of @_ -- init Undef, back-edge Unknown.
round_trips(<<'SRC', 'an undef init overwritten by a list element');
sub f { my $s; for my $x (@_) { $s = $x } return $s }
print f(1,2,3), "\n";
SRC

# Chalk::Bootstrap::Semiring::FilterComposite::_filter_compare: the body
# reads defined() on the carried value, and the back-edge is a branch merge.
round_trips(<<'SRC', 'a first-match latch read by defined in its own guard');
sub f { my $first; for my $x (@_) { $first = $x if !defined $first && $x > 1 } return $first // "none" }
print f(1,2,3), " ", f(0,1), "\n";
SRC

# Chalk::Bootstrap::Perl::Actions::PreIncDec and its siblings: a `//=` in a
# guarded arm.
round_trips(<<'SRC', 'a //= of a reference in a guarded arm');
sub f { my $t; for my $l (@_) { my $v = $l->[0]; if (defined $v && ref $v) { $t //= $v } } return $t ? $t->[0] : "none" }
print f([undef],[[5]],[[6]]), " ", f([1]), "\n";
SRC

# Chalk::Target::LLVM::Context::_emit_regex_matcher: the Int-init polarity.
round_trips(<<'SRC', 'an Int init conditionally overwritten by an element');
sub f { my $n = 0; for my $x (@_) { $n = $x if $x > $n } return $n }
print f(3,"7",2), "\n";
SRC

round_trips(<<'SRC', 'a while loop: Int init overwritten by an argument');
sub f { my ($a) = @_; my $i = 0; my $m = 0; while ($i < 3) { $m = $a->[$i] if $a->[$i] > $m; $i++ } return $m }
print f([4,9,2]), "\n";
SRC

# A CONSUMER READS THE CARRIED VALUE before the shift overwrites it: the
# stale-consumer shape the refusal guarded. Its Phi is unstamped from the
# start, so `$x + 1` was never stamped against an Int it did not have.
round_trips(<<'SRC', 'a value read before its loop-carried shift');
sub f { my $x = 1; my $y = 0; my $n = 2; while ($n > 0) { $y = $x + 1; $x = shift; $n = $n - 1 } $y }
print f(10,20), "\n";
SRC

# THE DECISION IS PER SLOT. An accumulator over a range keeps its Int stamp on
# the wire: the scout sees its back-edge stamped and leaves it optimistic.
subtest 'a counted accumulator keeps its Int Phi' => sub {
    my $m = graph_of('sub f { my $s = 0; for my $i (1..3) { $s = $s + $i } return $s } print f(), "\n";');
    my @phis = grep { $_->{op} eq 'Phi' } ($m->{methods}{'main::f'}{nodes} // [])->@*;
    ok scalar(@phis), 'there are loop Phis';
    is [grep { ($_->{stamp} // '') ne 'Int' } @phis], [], 'every one is Int';
};

done_testing;
