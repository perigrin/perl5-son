# ABOUTME: A return inside an if arm inside a loop body leaves the sub from that arm: the
# ABOUTME: arm records its exit in the function's exit list instead of refusing or dropping it.

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


sub refuses ($src, $why, $name) {
    my $data = graph_of($src);
    my $err  = producer_stderr();
    my $d    = SoN::Deparse->new;
    my $out  = $data ? $d->render($data) : undef;
    ok !defined $out, "$name: refuses" or diag $out;
    like $err . ($d->gap // ''), $why, "$name: names its cause";
}

# THE CLUSTER: chalk's Context::walk, Earley::_find_sync_point and two
# EmitHelpers methods refused "function exit inside a statement modifier in
# an if/else arm". The arm of a mid-body `if` was walked with no exit list, so
# a `return` anywhere inside it had nowhere to go. Every case returns on one
# call and falls through to the sub's own return on the other.
subtest 'a return nested in a loop-body arm' => sub {
    round_trips(q{sub f { my $k=shift; for my $i (1..5) { if ($i > 1) { return $i if $i > $k; } } return 0 } print f(2), " ", f(9), "\n";},
        'return if, in a foreach arm');
    round_trips(q{sub f { my $k=shift; for my $i (1..5) { if ($i > 1) { return $i unless $i <= $k; } } return 0 } print f(2), " ", f(9), "\n";},
        'return unless, in a foreach arm');
    round_trips(q{sub f { my $k=shift; for my $i (1..5) { if ($i > 1) { if ($i > $k) { return $i } } } return 0 } print f(2), " ", f(9), "\n";},
        'a block if around the return');
    round_trips(q{sub f { my $k=shift; my $i=0; while ($i < 5) { $i++; if ($i > 1) { return $i if $i > $k; } } return 0 } print f(2), " ", f(9), "\n";},
        'return if, in a while arm');
};

# The chalk graphs themselves, reduced.
subtest 'the chalk shapes' => sub {
    round_trips(q{sub walk { my @s=@_; while (@s) { my $n = pop @s; if ($n > 0) { my $r = $n * 2; return $r if $r > 5; next; } push @s, 7 if $n == -1; } return -1 } print walk(1, 4, 2), " ", walk(1, 2), " ", walk(-1, 1), "\n";},
        'Context::walk: return if, then next');
    round_trips(q{sub fx { my ($c)=@_; while (defined $c) { if ($c > 5) { my $d = $c * 2; return $d if $d > 16; return; } $c += 2 } return } print fx(9) // "u", " ", fx(3) // "u", "\n";},
        '_find_exists_delete_in_chain: return if, then return');
    round_trips(q{sub fs { my ($e, %m) = @_; if ($e =~ /^F(\d+)$/) { my $idx = $1; for my $k (sort keys %m) { if ($m{$k} == $idx) { return $k if $k ne 'z'; } } } return } print fs("F2", a => 1, b => 2) // "u", " ", fs("F9", a => 1) // "u", "\n";},
        '_field_sigil_for_expr: return if, two arms deep');
    # The whole of Context::walk, with its in-place reverse of the children.
    round_trips(q{sub walk { my ($root, $cb, %opts) = @_; my $reverse = $opts{reverse}; my @stack = ($root); while (@stack) { my $node = pop @stack; my $f = $node->{v}; if (defined $f) { my $result = $cb->($node); return $result if defined $result; next; } my @kids = @{ $node->{kids} }; @kids = reverse @kids unless $reverse; push @stack, @kids; } return undef; } sub big { my $v = $_[0]{v}; $v > 4 ? $v : undef } my $t = { kids => [ { v => 1 }, { kids => [ { v => 5 }, { v => 9 } ] } ] }; print walk($t, \&big) // "u", " ", walk($t, \&big, reverse => 1) // "u", " ", walk($t, sub { undef }) // "u", "\n";},
        'Context::walk, whole');
};

# A LIST EXIT FROM INSIDE A LOOP: a bare `return` beside a `return $x` makes
# the exit carry a list and its scalar reading. The renderer refused it; it
# returns both by the caller's context now, and the fall-through path binds
# the list half as an array, or an empty `return` gave a list caller (undef).
subtest 'a list exit from inside a loop' => sub {
    round_trips(q{sub fx { my ($c)=@_; while (defined $c) { if ($c > 5) { my $d = $c * 2; return $d if $d > 16; return; } $c += 2 } return } my @a = fx(9); my @b = fx(3); print scalar(@a), " ", scalar(@b), "\n";},
        'a bare return in the arm, to a list caller');
    round_trips(q{sub f { my ($k)=@_; for my $i (1..3) { return $i if $i > $k } return } my @a = f(1); my @b = f(5); print scalar(@a), " ", scalar(@b), "\n";},
        'a bare return after the loop, to a list caller');
    round_trips(q{sub f { my ($k)=@_; for my $i (1..3) { return if $i > $k } return 7 } my @a = f(1); my @b = f(5); my $s = f(1); print scalar(@a), " ", scalar(@b), " ", $s // "u", "\n";},
        'a bare return in the loop, both contexts');
};

# A RETURN IN AN ELSE ARM IN A LOOP BODY went into a throwaway list: the arm
# still converged, the list was dropped, and the return vanished -- the IR had
# no Constant 5 and the program printed `x x` then `0 0` where perl prints
# `x x 5 0`. A refusal is the floor; a round trip is the goal.
subtest 'a return in an else arm in a loop body is not dropped' => sub {
    round_trips(q{sub f { my $k=shift; for my $i (1..3) { if ($i > 1) { print "x\n"; } else { return 5 if $i > $k; } } return 0 } print f(0), " ", f(9), "\n";},
        'return if, in an else arm');
};

done_testing;
