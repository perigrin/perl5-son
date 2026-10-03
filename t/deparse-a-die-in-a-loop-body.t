# ABOUTME: A `die` guarded by an `if` inside a loop body dies: the arm's Unwind is built,
# ABOUTME: not skipped -- in a foreach or a while, block or postfix form.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

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


# _walk_branch BUILT AN Unwind FOR `die` ONLY ON A VALUE ARM, and the loop
# body's guarded-statement walk is not one -- so the die was stepped past and
# vanished: `for my $x (@_) { die "big\n" if $x > 1 }` returned "ok" where
# perl dies. chalk's loops guard their invariants exactly so.
round_trips(<<'SRC', 'a postfix die in a foreach');
sub f { for my $x (@_) { die "big\n" if $x > 1; } return "ok" } print eval { f(1, 9) } // $@;
SRC

round_trips(<<'SRC', 'a block die in a foreach');
sub f { for my $x (@_) { if ($x > 1) { die "big\n" } } return "ok" } print eval { f(1, 9) } // $@;
SRC

round_trips(<<'SRC', 'a die before more of the body');
sub f { for my $x (@_) { die "big\n" if $x > 1; print "s$x\n"; } return "ok" } print eval { f(1, 9) } // $@;
SRC

round_trips(<<'SRC', 'a die in a while');
sub f { my $i = 0; while ($i < 3) { $i++; die "big\n" if $i > 1 } return "ok" } print eval { f() } // $@;
SRC

round_trips(<<'SRC', 'a die unless');
sub f { for my $x (@_) { die "small\n" unless $x > 1; } return "ok" } print eval { f(5, 0) } // $@;
SRC

# A DEMOTED ITERATOR IS WRITTEN BACK -- a callee may have changed it through
# $_[0] -- and the write-back ran every pass, so iterating read-only values
# (a sub's @_ holding constants) died "Modification of a read-only value"
# where perl, which never wrote, ran on. It writes only a changed value; a
# callee that changed a read-only one dies in perl as well.
round_trips(<<'SRC', 'an iterator passed to a call, over read-only values');
sub g { $_[0] } sub f { my $o = ""; for my $x (@_) { next unless g($x) && g($x) > 1; $o .= $x } return $o } print f(1, 2, 3), "\n";
SRC

round_trips(<<'SRC', 'a callee that changes the iterator still writes back');
sub bump { $_[0]++ } my @a = (1, 2); for my $x (@a) { bump($x) } print "@a\n";
SRC

done_testing;
