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

# A RETURN DIRECTLY IN AN IF/ELSE OR TERNARY ARM: the exit list let it
# through, but no If was built for it -- only a NESTED return counted -- so
# the exit hung off the pre-branch control. In a loop body that is a return
# on the first iteration: `100 100` where perl prints `300 15`. And with the
# true arm gone, the walk resumed at the false arm's FIRST op rather than its
# end, so the staying arm's value and stores were lost (`300 0`, `100 0`).
subtest 'a return directly in an if/else or ternary arm' => sub {
    round_trips(q{sub f { my $k=shift; my $s=0; for my $i (1..5) { my $v = $i > $k ? (return $i*100) : $i; $s += $v } return $s } print f(2), " ", f(9), "\n";},
        'my $v = C ? (return X) : Y, in a loop');
    round_trips(q{sub f { my $k=shift; my $s=0; for my $i (1..5) { $s += $i > $k ? (return $s) : $i } return -$s } print f(2), " ", f(9), "\n";},
        '$s += C ? (return X) : Y, in a loop');
    round_trips(q{sub f { my $k=shift; my @o; for my $i (1..5) { push @o, ($i > $k ? (return "r$i") : $i) } return "@o" } print f(2), " ", f(9), "\n";},
        'push @o, (C ? (return X) : Y), in a loop');
    round_trips(q{sub f { my $k=shift; my $s=0; for my $i (1..5) { my $v = $i <= $k ? $i : (return $i); $s += $v } return $s } print f(2), " ", f(9), "\n";},
        'the false arm returns, in a loop');
    round_trips(q{sub f { my $k=shift; my ($s,$i)=(0,0); while ($i < 5) { $i++; my $v = $i > $k ? (return $i) : $i; $s += $v } return $s } print f(2), " ", f(9), "\n";},
        'a consumed ternary, in a while body');
    round_trips(q{sub f { my $k=shift; my $s=0; for my $i (1..5) { $i > $k ? (return $i*100) : ($s += $i); } return $s } print f(2), " ", f(9), "\n";},
        'a void ternary, in a loop');
    round_trips(q{sub f { my $k=shift; my $s=0; for my $i (1..5) { if ($i > $k) { return $i*100 } else { $s += $i } } return $s } print f(2), " ", f(9), "\n";},
        'if/else, the true arm returns, in a loop');
    round_trips(q{sub f { my $k=shift; my $s=0; for my $i (1..5) { if ($i <= $k) { $s += $i } else { return $s } } return -$s } print f(2), " ", f(9), "\n";},
        'if/else, the false arm returns, in a loop');
    round_trips(q{sub f { my $k=shift; my @o; for my $i (1..5) { if ($i > $k) { return @o } else { push @o, $i } } return () } my @a=f(2); my $n=f(2); print "@a|$n\n";},
        'if/else returning an array, in a loop');
    round_trips(q{sub f { my $s=0; if ($_[0] > 1) { return 100 } else { $s += 1 } return $s } print f(2), " ", f(0), "\n";},
        'if/else, the true arm returns, no loop');
    round_trips(q{sub f { my $v = $_[0] > 1 ? (return 100) : 7; $v + 1 } print f(2), " ", f(0), "\n";},
        'a consumed ternary, no loop');
    # A RETURN UNDER A FURTHER BRANCH leaves an arm that still yields a value
    # on its other path; merging that value is not lowered, and counting the
    # return as the arm's own gave `$s + undef`.
    my $why = qr/GAP: a consumed value-context ternary/;
    refuses(q{sub f { my $k=shift; my $s=0; for my $i (1..5) { my $v = $i > $k ? ($i > 4 ? (return 1) : 2) : $i; $s += $v } return $s } print f(2), " ", f(9), " ", f(4), "\n";},
        $why, 'a nested ternary return, consumed, in a loop');
    refuses(q{sub f { my $k=shift; my $v = $k > 1 ? ($k > 4 ? (return 1) : 2) : $k; $v + 10 } print f(0), " ", f(2), " ", f(5), "\n";},
        $why, 'a nested ternary return, consumed, no loop');
    round_trips(q{sub f { my $k=shift; my $s=0; for my $i (1..5) { if ($i > $k) { if ($i > 4) { return 1 } else { $s += 2 } } else { $s += $i } } return $s } print f(2), " ", f(9), " ", f(4), "\n";},
        'a nested if/else return, in a loop');
};

# AN AGGREGATE EXIT FALLING THROUGH A LOOP: `return @o` after a loop that
# also returns from inside was bound `my $ret = @o; return $ret` -- the count,
# to a list caller too. Every input an array (or every one a hash) binds an
# array (a hash); an aggregate beside a scalar would need the caller's context
# to pick, and refuses by name.
subtest 'an aggregate exit after a loop' => sub {
    round_trips(q{sub f { my $k=shift; my @o; for my $i (1..4) { if ($i > 1) { push @o, $i; return @o if $i > $k } } return @o } my @a=f(2); my $n=f(2); my @b=f(9); print "@a|$n|@b\n";},
        'return @o, in an arm and after the loop');
    round_trips(q{sub f { my $k=shift; my @o; for my $i (1..4) { push @o, $i; return @o if $i > $k } return @o } my @a=f(2); my $n=f(2); my @b=f(9); my $m=f(9); print "@a|$n|@b|$m\n";},
        'return @o, in the body and after the loop');
    round_trips(q{sub f { my $k=shift; my @o; my $i=0; while ($i < 4) { $i++; push @o, $i; return @o if $i > $k } return @o } my @a=f(2); my @b=f(9); my $m=f(9); print "@a|@b|$m\n";},
        'return @o, from a while loop');
    round_trips(q{sub f { my $k=shift; my %h=(a=>1); for my $i (1..4) { $h{$i}=1; return %h if $i > $k } return %h } my %a=f(2); my @b=f(9); print scalar(keys %a), "|", scalar(@b), "\n";},
        'return %h, in the body and after the loop');
    refuses(q{sub f { my $k=shift; my @o; for my $i (1..4) { push @o, $i; return $i if $i > $k } return @o } my @a=f(2); my $n=f(2); my @b=f(9); my $m=f(9); print "@a|$n|@b|$m\n";},
        qr/GAP: a function exit merges an aggregate with a scalar/, 'return $i in the loop, @o after it');
};

# A RETURNED HASH IS THE HASH AS IT STANDS. The list half of `return %h`
# flattened the literal's inputs -- the hash as first built -- so a store or
# a delete since was lost: `my %h=(a=>1); $h{b}=2; return %h` returned a => 1.
# From inside a loop the list exit reaches the renderer now, and printed it.
subtest 'a returned hash after a store or a delete' => sub {
    round_trips(q{sub f { my %h=(a=>1); $h{b}=2; return %h } my %a=f(1); print join(",", sort keys %a), "\n";},
        'a store, then return %h');
    round_trips(q{sub f { my %h=(a=>1); $h{b}=2; return %h if $_[0]; $h{c}=3; return %h } my %a=f(1); my %b=f(0); print join(",", sort keys %a), "|", join(",", sort keys %b), "\n";},
        'two returns of %h around a store');
    round_trips(q{sub f { my %h=(a=>1); for my $i (1..3) { $h{$i}=1; return %h if $i > $_[0] } return 5 } my %a=f(1); print join(",", sort keys %a), "\n";},
        'return %h from a loop');
    round_trips(q{sub f { my %h=(a=>1,b=>2); delete $h{a}; return %h } my %a=f(); print join(",", sort keys %a), "\n";},
        'a delete, then return %h');
    round_trips(q{sub f { my %h=(a=>1,b=>2,c=>3); delete @h{qw(a b)}; return %h } my %a=f(); print join(",", sort keys %a), "\n";},
        'a slice delete, then return %h');
    round_trips(q{sub f { my $k=shift; my %h=(1=>1,2=>2,3=>3,4=>4); for my $i (1..4) { delete $h{$i}; return %h if $i > $k } return %h } my %a=f(2); my @b=f(9); print join(",", sort keys %a), "|", scalar(@b), "\n";},
        'a delete in a loop, return %h in and after it');
};

# AN AGGREGATE RETURNED FROM INSIDE A LOOP IS THE AGGREGATE AS IT STANDS on
# that iteration. The return was walked before the loop's own mutations (a
# push after it, or one on an earlier iteration), so the flatten shortcut
# returned the literal as first built: `return @o if ...; push @o, $i` gave
# (1) where perl gives (1, 1, 2).
subtest 'an aggregate returned from inside a loop that mutates it' => sub {
    round_trips(q{sub f { my $k=shift; my @o=(1); for my $i (1..5) { if ($i > 1) { return @o if $i > $k; push @o, $i } } return scalar(@o) } my @a=f(2); my @b=f(9); my $n=f(9); print "@a|@b|$n\n";},
        'return @o in an arm, push after it');
    round_trips(q{sub f { my $k=shift; my @o=(1); for my $i (1..5) { if ($i > 1) { $o[0]++; return @o if $i > $k } } return 0 } my @a=f(2); my $n=f(2); print "@a|$n\n";},
        'an element store, then return @o in an arm');
    round_trips(q{sub f { my $k=shift; my %h=(a=>1); for my $i (1..5) { if ($i > 1) { return %h if $i > $k; $h{$i}=1 } } return 0 } my %a=f(2); print join(",", sort keys %a), "\n";},
        'return %h in an arm, a store after it');
    round_trips(q{sub f { my $k=shift; my @o=(1); for my $i (1..5) { return @o if $i > $k; push @o, $i } return 0 } my @a=f(2); my $n=f(2); print "@a|$n\n";},
        'return @o in the body, push after it');
    round_trips(q{sub f { my $k=shift; my @o=(1); for my $i (1..5) { $o[0]++; return @o if $i > $k } return 0 } my @a=f(2); my $n=f(2); print "@a|$n\n";},
        'an element store, then return @o in the body');
    round_trips(q{sub f { my $k=shift; my @o=(1,2); for my $i (1..5) { if ($i > 1) { return @o if $i > $k; pop @o } } return 0 } my @a=f(2); my $n=f(2); print "@a|$n\n";},
        'return @o in an arm, pop after it');
    round_trips(q{sub f { my $k=shift; my @o=(1); my $i=0; while ($i < 5) { $i++; return @o if $i > $k; unshift @o, $i } return 0 } my @a=f(2); print "@a\n";},
        'return @o from a while loop, unshift after it');
    round_trips(q{sub f { my $k=shift; my %h=(a=>1); for my $i (1..5) { return %h if $i > $k; delete $h{a} } return 0 } my %a=f(2); print join(",", sort keys %a), "|\n";},
        q{return %h in the body, a delete after it});
    round_trips(q{sub f { my $k=shift; my @o=(1,2); for my $i (1..5) { if ($i > 1) { last if $i > $k; pop @o } } return scalar(@o) } print f(2), "\n";},
        q{last if in an arm, pop after it});
    round_trips(q{sub f { my $k=shift; my @o=(1,2); for my $i (1..5) { if ($i > 1) { return 7 if $i > $k; shift @o } } return 0 } print f(2), "\n";},
        q{return a scalar in an arm, shift after it});
};

# A LIST TERNARY WITH A RETURNING ARM yields the OTHER arm's whole list. The
# surviving arm was taken as one value, so `my @r = $k > 2 ? (return "x") :
# (3,4)` bound (4).
subtest 'a list ternary whose other arm returns' => sub {
    round_trips(q{sub f { my $k=shift; my @r = $k > 2 ? (return "x") : (3,4); return "@r" } print f(1), f(5), "\n";},
        'my @r = C ? (return) : (3,4)');
    round_trips(q{sub f { my $k=shift; my @r = $k > 2 ? (return (1,2)) : (3,4); return scalar(@r) } my @a=f(5); my @b=f(1); print "@a|@b\n";},
        'a list returned, scalar(@r) after');
    round_trips(q{sub f { my $k=shift; my @r = ($k>2 ? (return 'x') : (3,4)); return scalar(@r) } print f(1), f(5), "\n";},
        'parenthesised');
    round_trips(q{sub f { my $k=shift; my ($a,$b) = $k>2 ? (return 'x') : (3,4); return "$a$b" } print f(1), f(5), "\n";},
        'my ($a, $b) = ...');
    round_trips(q{sub f { my $k=shift; my @r = $k>2 ? (5,6) : (return 'y'); return "@r" } print f(1), f(5), "\n";},
        'the returning arm second');
    round_trips(q{sub f { my $k=shift; my $r = $k > 2 ? (return "x") : 7; return $r } print f(1), f(5), "\n";},
        'a scalar ternary still lowers');
    round_trips(q{sub f { my $k=shift; my %h = $k > 2 ? (return "x") : (a=>1, b=>2); return join(",", sort keys %h) } print f(1), f(5), "\n";},
        q{my %h = C ? (return) : (a=>1, b=>2)});
    round_trips(q{sub f { my $k=shift; my @r = (1, ($k > 2 ? (return "x") : (3,4)), 9); return "@r" } print f(1), f(5), "\n";},
        q{inside a longer list});
    refuses(q{sub f { $_[0] > 2 ? (return "x") : (3,4) } my @a=f(1); my $s=f(1); print "@a|$s|", f(5), "\n";},
        qr/GAP: a ternary whose other arm leaves yields a multi-element list in its caller's context/, q{the sub's last statement});
};

done_testing;
