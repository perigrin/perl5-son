# ABOUTME: A signature default that allocates, calls or dies is a branch on the
# ABOUTME: argument: it runs only when the argument is absent, undef or false.

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
    graph_of($src);
    like producer_stderr(), $why, $name;
}

# A FRESH ALLOCATION PER CALL: a shared [] would print 123.
my $alloc = q{use v5.36; sub f ($x, $y = []) { push @$y, $x; scalar @$y } print f(1), f(1), f(1,[2,3]), "\n";};
round_trips($alloc, 'an allocating default is fresh on each call');
emits_quietly($alloc, 'an allocating default');

# THE DIE RUNS ON undef AND ON absent, never on a value.
round_trips(q{use v5.36; sub f ($r //= die "no repr\n") { "<$r>" } print f("Int"), "\n"; print eval { f(undef) } // $@; print eval { f() } // $@;},
    'a dying //= default');

# AN EXPLICIT undef IS AN ARGUMENT: the call runs once, for f().
my $call = q{use v5.36; our $calls = 0; sub g { $calls++; 7 } sub f ($x = g()) { $x } print f(), f(1), f(undef) // "u", " calls=$calls\n";};
round_trips($call, 'a calling default runs only when the argument is absent');
emits_quietly($call, 'a calling default');

round_trips(q{use v5.36; our $calls = 0; sub g { $calls++; 7 } sub f ($x ||= g()) { $x } print f(0), f(1), f(), " calls=$calls\n";},
    'a calling ||= default runs on a false argument');

# A LATER DEFAULT READS AN EARLIER PARAMETER, and runs after it is bound.
round_trips(q{use v5.36; sub f ($x, $y = [$x]) { push @$y, 9; "@$y" } print f(1), " ", f(2, [3]), "\n";},
    'a default reads an earlier parameter');

round_trips(q{use v5.36; sub f ($x, $y //= [$x]) { "@$y" } print f(1), f(1,undef), f(1,[2]), "\n";},
    'an allocating //= default');

# AN ANONYMOUS SUB has no declared signature to fold into.
round_trips(q{use v5.36; my $f = sub ($x, $y = []) { push @$y, $x; scalar @$y }; print $f->(1), $f->(1), $f->(1,[2,3]), "\n";},
    'an allocating default in an anonymous sub');

# A METHOD'S @_ starts after the invocant.
round_trips(q{use v5.42; use experimental "class"; class C { method m ($a, $b = []) { push @$b, $a; scalar @$b } } my $c = C->new; print $c->m(1), $c->m(1), $c->m(1,[5]), "\n";},
    'an allocating method default');

# THE PROGRAM'S OWN @_ COUNT keeps perl's experimental warning; only the
# count the branch synthesizes is quieted.
sub warns_like_perl ($src, $name) {
    my $out = SoN::Deparse->new->render(graph_of($src) // {}) // return fail "$name: renders";
    my $warn = sub ($s) {
        my $f = "$dir/w." . int(rand 1e9) . ".pl";
        open my $fh, '>', $f or die $!; print $fh $s; close $fh;
        my $e = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
        return [ map { s/ at \S+ line \d+\.\z//r } split /\n/, $e ];
    };
    is $warn->($out), $warn->($src), "$name: the same warnings as perl";
}
warns_like_perl(q{use v5.36; sub k ($a) { scalar(@_) } print k(1), "\n";},
    'a counted @_ with no default');
warns_like_perl(q{use v5.36; sub k ($a = [1]) { scalar(@_) . scalar(@$a) } print k(), k([2,3]), "\n";},
    'a counted @_ beside an allocating default');
warns_like_perl(q{use v5.36; sub k ($a, $b = []) { scalar(@_) } print k(1), k(1,2), "\n";},
    'a counted @_ beside a present test');
warns_like_perl($alloc, 'an allocating default');

# A DEMOTED PARAMETER -- referenced, or passed on to a call -- is stored
# into its slot from the branch's value. The signature declares it; a
# second `my` masks it.
for my $case (
    [q{use v5.36; sub f ($x = []) { my $r = \$x; $$r = [7]; "@$x" } print f(), f([0]), "\n";},
        'a referenced parameter with an allocating default'],
    [q{use v5.36; sub f ($n, $acc = []) { return $acc if !$n; push @$acc, $n; f($n-1, $acc) } print "@{f(3)}", "\n";},
        'a recursing parameter with an allocating default'],
    [q{use v5.36; sub f ($x //= [1]) { my $r = \$x; push @$$r, 2; "@$x" } print f(), f(undef), f([0]), "\n";},
        'a referenced parameter with an allocating //= default'],
    [q{use v5.36; our $c = 0; sub g { $c++; 5 } sub f ($x = g()) { my $r = \$x; $$r++; $x } print f(), f(1), " c=$c\n";},
        'a referenced parameter with a calling default'],
) {
    round_trips(@$case);
    emits_quietly(@$case);
}

# A CLOSURE OVER THE PARAMETER has nowhere to read the branch's value from.
for my $src (
    q{use v5.36; sub f ($x = []) { my $s = sub { push @$x, 1 }; $s->(); "@$x" } print f(), f([0]), "\n";},
    q{use v5.36; sub f ($y = []) { push @$y, 1; sub { scalar @$y } } print f()->(), f([0])->(), "\n";},
    q{use v5.36; our $c = 0; sub g { $c++; 5 } sub f ($x = g()) { my $s = sub { $x + 1 }; $s->() } print f(), f(1), "\n";},
) {
    refuses($src, qr/GAP: a signature default with an effect, on a parameter a closure captures/,
        'a captured parameter with an effectful default refuses');
}

# A `return` IN A DEFAULT leaves the sub; the branch has no exit to record it.
refuses(q{use v5.36; sub f ($x = return "early") { "late" } print f(), " ", f(1), "\n";},
    qr/GAP: a `return` in an arm with no function exit/,
    'a returning default refuses');

# A STRING EVAL reads the parameter's pad slot by name at run time; the
# branch's value never reaches it.
for my $src (
    q{use v5.36; sub f ($x = []) { eval q{push @$x, 3}; "@$x" } print f(), f([0]), "\n";},
    q{use v5.36; our $c=0; sub g { $c++; 4 } sub f ($x = g()) { eval '$x' } print f(), f(1), " c=$c\n";},
    q{use v5.36; sub f ($x = [2]) { my $s='$x->[0]'; eval $s } print f(), f([5]), "\n";},
    q{use v5.36; sub f ($x //= [2]) { my $s='$x->[0]'; eval $s } print f(), f(undef), f([5]), "\n";},
    q{use v5.36; sub f ($t, $x = [$t]) { eval { 1 }; eval "\$t" . '+' . "\$x->[0]" } print f(1), f(1,[5]), "\n";},
) {
    refuses($src, qr/GAP: a signature default with an effect, in a sub with a string eval/,
        'a string eval beside an effectful default refuses');
}
# A BLOCK eval reads nothing by name.
round_trips(q{use v5.36; sub f ($x = [1]) { eval { push @$x, 2 }; "@$x" } print f(), f([0]), "\n";},
    'a block eval beside an allocating default');

# A LIST CONSUMER OF THE MERGED VALUE follows the branch that assigns it.
for my $case (
    [q{use v5.36; sub f ($x = [1]) { my @l = ($x) x 2; push @{$l[0]}, 2; "@$x" } print f(), f([0]), "\n";},
        'a repeated parameter with an allocating default'],
    [q{use v5.36; our $c=0; sub g { $c++; 4 } sub f ($x = g()) { my @l = (1) x $x; scalar @l } print f(), f(1), " c=$c\n";},
        'a repeat count from a calling default'],
    [q{use v5.36; sub f ($x = []) { my @l = reverse($x); push @{$l[0]}, 1; "@$x" } print f(), f([0]), "\n";},
        'a reversed parameter with an allocating default'],
    [q{use v5.36; sub f ($t, $x = $t ? [1] : [2]) { my @l = reverse($x); push @{$l[0]}, 1; "@$x" } print f(0), f(1), "\n";},
        'a reversed parameter with a ternary default'],
    [q{use v5.36; sub f ($x = [3,1,2]) { my @l = sort { $a <=> $b } @$x; "@l" } print f(), f([9,8]), "\n";},
        'a sorted deref of an allocating default'],
    [q{use v5.36; sub f ($x = [1]) { my %h = (k => $x); push @{$h{k}}, 2; "@$x" } print f(), f([0]), "\n";},
        'a hash holding an allocating default'],
    [q{use v5.36; sub f ($x = [1]) { my @l = map { $_ } ($x, $x); push @{$l[1]}, 2; "@$x" } print f(), f([0]), "\n";},
        'a mapped allocating default'],
    [q{sub g {[2]} sub f { my $x = $_[0] ? [1] : g(); my @l = reverse($x); push @{$l[0]}, 1; "@$x" } print f(0), f(1), "\n";},
        'a reversed ternary over a call'],
) {
    round_trips(@$case);
}

# A LATER DEFAULT READING A BRANCHED PARAMETER reads the merged value.
for my $case (
    [q{use v5.36; sub f ($x = [], $y = $x) { push @$y, 1; "@$x" } print f(), f([0]), f([0],[]), "\n";},
        'a plain default over an allocating one'],
    [q{use v5.36; sub f ($x = [], $y = scalar @$x) { push @$x, 1; "$y@$x" } print f(), f([0]), f([0],5), "\n";},
        'a counted default over an allocating one'],
    [q{use v5.36; our $c=0; sub g { $c++; 4 } sub f ($x = g(), $y = $x + 1, $z = $y * 2) { "$x$y$z" } print f(), f(1), f(1,1), " c=$c\n";},
        'a chain of plain defaults over a calling one'],
    [q{use v5.36; sub f ($x //= [1], $y //= $x) { push @$y, 2; "@$x" } print f(), f(undef, undef), f([0]), "\n";},
        'a //= default over an allocating //= one'],
    [q{use v5.36; sub f ($x = [], $y = 7) { push @$x, $y; "@$x" } print f(), f([0]), f([0], 1), "\n";},
        'an unrelated plain default after an allocating one'],
) {
    round_trips(@$case);
}

# AN INNER `my` SHADOWING A PARAMETER is a new variable on each pass; the
# signature's declaration of the parameter does not reach into the block.
for my $case (
    [q{use v5.36; sub f ($x) { my @r; for my $i (1..3) { my $x = $i; push @r, \$x } join(",", map { $$_ } @r) . "/$x" } print f(9), "\n";},
        'an inner my shadows a plain parameter'],
    [q{use v5.36; sub f ($x = 1) { my @r; my $i = 0; while ($i++ < 3) { my $x = $i; push @r, \$x } join(",", map { $$_ } @r) . "/$x" } print f(9), f(), "\n";},
        'an inner my in a while shadows a defaulted parameter'],
    [q{use v5.36; sub f ($x) { my $r = \$x; my @l; for (1..2) { my $x = $_; push @l, \$x } $$r = 0; join ",", $x, map { $$_ } @l } print f(5), "\n";},
        'an inner my shadows a referenced parameter'],
    [q{use v5.36; our $c=0; sub g { $c++; 7 } sub f ($x = g()) { my @r; for my $i (1..2) { my $x = $i; push @r, \$x } join(",", map { $$_ } @r) . "/$x" } print f(), f(3), " c=$c\n";},
        'an inner my shadows a parameter with a calling default'],
    [q{use v5.36; sub f ($x = []) { my $q = \$x; my @r; for my $i (1..2) { my $x = $i; push @r, \$x } join(",", map { $$_ } @r) . "/" . scalar(@$x) } print f(), f([1]), "\n";},
        'an inner my shadows a referenced parameter with an allocating default'],
) {
    round_trips(@$case);
}

# s///ee EVALUATES ITS REPLACEMENT AS A STRING, by name, with no entereval.
for my $src (
    q{use v5.36; our $c=0; sub g { $c++; 3 } sub f ($x = g()) { my $r = '"[$x]"'; my $s = "a"; $s =~ s/a/$r/ee; $s } print f(), f(1), " c=$c\n";},
    q{use v5.36; sub f ($x = [3]) { my $s = "a"; $s =~ s/a/'$x->[0]'/ee; $s } print f(), f([1]), "\n";},
    q{use v5.36; sub f ($x //= [3]) { my $s = "ab"; $s =~ s/a/'$x->[0]'/eei; $s } print f(), f([1]), "\n";},
) {
    refuses($src, qr/GAP: a signature default with an effect, in a sub with a string eval/,
        'an s///ee beside an effectful default refuses');
}
round_trips(q{use v5.36; sub f ($x = [3]) { my $s = "a"; $s =~ s/a/$x->[0]/e; $s } print f(), f([1]), "\n";},
    'an s///e beside an allocating default');

# A SUB THAT ENDS ON AN EXPLICIT undef returns it: one element to a list.
for my $case (
    [q{use v5.36; our $c=0; sub g { $c++; undef } sub f ($x //= g()) { $x // 'u' } print f(), f(0), f(1), " c=$c\n";},
        'a //= default calling a sub that ends on undef'],
    [q{use v5.36; our $c=0; sub g { $c++; undef } sub f ($x = g()) { $x // 'u' } print f(), f(0), f(1), " c=$c\n";},
        'a calling default whose sub ends on undef'],
    [q{use v5.36; our $c=0; sub g { $c++; undef } sub f ($x ||= g()) { $x // 'u' } print f(), f(0), f(1), " c=$c\n";},
        'a ||= default whose sub ends on undef'],
    [q{use v5.36; our $c=0; sub g { $c++; undef } sub f ($x) { $x // 'u' } print f(g()), " c=$c\n";},
        'a sub ending on undef passed on'],
    [q{our $c=0; sub g { $c++; undef } my @a = g(); sub h { } my @b = h(); print scalar(@a), scalar(@b), defined(g()) ? 'd' : 'u', " c=$c\n";},
        'an explicit undef is one element; an empty body none'],
) {
    round_trips(@$case);
}

done_testing;
