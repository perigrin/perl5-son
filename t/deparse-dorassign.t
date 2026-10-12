# ABOUTME: `//=`, `||=` and `&&=` round trip into an element, inside a loop body or an
# ABOUTME: if arm, and with a right side that calls; the right side runs only when stored.

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

# AN ELEMENT TARGET IS FETCHED AS AN LVALUE, and that fetch creates the slot
# before the test: `keys` in the right side sees it, and `&&=` on an absent
# key leaves it existing although nothing is stored.
round_trips(<<'SRC', 'an element target: the call runs once, the slot vivifies');
my %h = (a => 0); my $n = 0; sub f { $n++; [$n] }
$h{a} //= f(); $h{b} //= f(); $h{b} //= f();
my %k; $k{x} //= scalar(keys %k); my %m; $m{q} &&= 1;
print "$h{a} $h{b}[0] $n $k{x} ", (exists $m{q} ? "viv" : "noviv"), "\n";
SRC
round_trips(<<'SRC', 'an array element target sees its own extension');
my @a = (1); $a[3] //= scalar(@a); print "@a[0,3] ", scalar(@a), "\n";
SRC
round_trips(<<'SRC', 'a nested element target, ||= and &&=');
my $r = {}; $r->{x}{y} //= 1; $r->{x}{y} ||= 5; $r->{x}{z} ||= 7; $r->{x}{y} &&= 3;
print join(",", map { "$_=$r->{x}{$_}" } sort keys $r->{x}->%*), "\n";
SRC
round_trips(<<'SRC', 'the memo idiom in value context');
my %cache; my $made = 0;
sub get { my ($k) = @_; return ($cache{$k} //= do { $made++; "v$k" }) }
print get("a"), get("b"), get("a"), " $made\n";
SRC
round_trips(<<'SRC', 'a key with an effect is computed once');
my %h; my $n = 0; sub k { $n++; "k" } $h{k()} //= 1; $h{k()} //= 2; print "$h{k} $n\n";
SRC
round_trips(<<'SRC', 'a closure over a hash, chalk TypeInference::_ctx shape');
{ my %c; my $n = 0; sub ctx { my ($t) = @_; my $key = "s:$t"; return ($c{$key} //= { t => $t, n => ++$n }) } }
print ctx("a")->{n}, ctx("b")->{n}, ctx("a")->{n}, "\n";
SRC

round_trips(<<'SRC', '||= whose right side reads the false slot it replaces');
my %h = (a => 0); $h{a} ||= $h{a} + 5; $h{b} ||= exists $h{b} ? "E" : "N"; print "$h{a} $h{b}\n";
SRC

# INSIDE A LOOP BODY.
round_trips(<<'SRC', 'an element //= feeding a push, in a loop body');
my %d; for my $n (qw(a b a)) { push @{ $d{$n} //= [] }, 1 }
print join(",", map { "$_=" . scalar(@{$d{$_}}) } sort keys %d), "\n";
SRC
round_trips(<<'SRC', 'a lexical and an element //= in a loop body');
my %d; my $x; my $s = 0;
for my $n (qw(a b a)) { $x //= $n; $d{$n} //= 0; $d{$n}++; $s++ }
print join(",", map {"$_=$d{$_}"} sort keys %d), " $x $s\n";
SRC

# INSIDE AN IF ARM.
round_trips(<<'SRC', 'a //= in an if/else arm');
sub h { my ($c, $d) = @_; my $x = $d; if ($c) { $x //= 1 } else { $x = 2 } return $x }
print h(1, undef), h(1, 5), h(0, 7), "\n";
SRC
round_trips(<<'SRC', 'a //= in a one-armed if');
sub g { my ($c, $d) = @_; my $x = $d; if ($c) { $x //= 5 } return $x // "u" }
print g(1, undef), g(0, undef), g(1, 2), "\n";
SRC

round_trips(<<'SRC', 'an element //= in an if arm');
sub g { my ($c, $h) = @_; if ($c) { $h->{x} //= []; push $h->{x}->@*, 1 } else { $h->{y} = 1 } return join ",", sort keys %$h }
print g(1, {}), " ", g(0, {}), "\n";
SRC

# A RIGHT SIDE THAT CALLS RUNS ONLY WHEN THE STORE HAPPENS.
round_trips(<<'SRC', '||= whose right side calls');
sub f2 { print "f\n"; 9 } my $x = 0; my $y = 3;
$x ||= f2(); $y ||= f2(); print "$x $y\n";
SRC
round_trips(<<'SRC', '//= whose right side calls, a singleton');
my $one; my $n = 0; sub mk { $n++; "o" }
sub one { $one //= mk(); return $one } print one(), one(), " $n\n";
SRC

# THE STORE IS A MUTATION OF THE AGGREGATE: a read after the loop must not
# take the flatten shortcut back to the initialiser literal.
round_trips(<<'SRC', '||= and //= into an array initialised from a list, in a for body');
my @a = (0, 1, undef); for my $i (0..2) { $a[$i] ||= 10 + $i }
my @b = (5); for my $i (0..3) { $b[$i] //= $i }
my @c = (1, 0); $c[1] ||= 4; print "@a|@b|@c\n";
SRC

# EACH READ IS ITS OWN NODE: an earlier read of the same slot at the same
# memory, or the value read of a first logassign, must not be pinned twice.
round_trips(<<'SRC', 'a defined test before the //= of the same element');
my @a = (1, undef); my $c = 0; $c++ unless defined $a[1]; $a[1] //= 0;
my @b = (1, undef, 3); my $d = 0; for my $i (0..2) { $d++ unless defined $b[$i]; $b[$i] //= 0 }
print "$c @a|$d @b\n";
SRC
round_trips(<<'SRC', 'two logassigns on one slot in one expression');
my %h; my %g = (a => 0); my %k = (a => 1); my @l;
push @l, ($h{a} //= 2) + ($h{a} //= 3), ($g{a} ||= 2) + ($g{a} ||= 2);
push @l, ($k{a} &&= 0) + ($k{a} &&= 5), ($h{b} //= 1), ($h{b} //= 2);
print "@l\n";
SRC

# A RIGHT SIDE THAT REBINDS ANOTHER LEXICAL rebinds it only when it runs.
round_trips(<<'SRC', 'a right side that rebinds a lexical, at top level and in an if arm');
sub t { my ($c, $x) = @_; my $n = 0; if ($c) { $x //= do { $n++; 4 } } return "$x$n" }
sub u { my ($c, $x) = @_; my $n = 0; if ($c) { $x ||= ++$n } return "$x$n" }
sub v { my ($c, $x) = @_; my $n = 0; if ($c) { $x &&= ($n = 5) } return "$x$n" }
my $x = 0; my $n = 0; $x ||= ($n = 3); my $y = 1; my $m = 0; $y ||= ($m = 3);
print t(1, undef), t(1, 2), u(1, 0), u(1, 2), v(1, 1), v(1, 0), " $x$n$y$m\n";
SRC

# BOTH ARMS OF AN IF: one If per logassign, not two successors on one node.
round_trips(<<'SRC', 'an element logassign in both arms of an if/else');
sub t { my ($c) = @_; my %h; if ($c) { $h{a} //= 3 } else { $h{a} //= 4 } return $h{a} }
sub u { my ($c) = @_; my %h; if ($c) { $h{a} ||= 3 } else { $h{a} &&= 4 } return $h{a} // 'u' }
print t(1), t(0), u(1), u(0), "\n";
SRC
round_trips(<<'SRC', 'a class field //= in a one-armed if');
use experimental 'class';
class C { field $x; method m ($c) { if ($c) { $x //= 7 } return $x // 'u' } }
my $o = C->new; print $o->m(0), $o->m(1), "\n";
SRC

# STILL REFUSED.
refuses('my %h; my $f = sub { $h{$_[0]} //= $_[1] }; my @r = ($f->("a", 1), $f->("a", 2)); print "@r\n";',
    qr/GAP: `\/\/=` into an element of an aggregate an anon sub closes over/,
    'an element of a captured hash in an anon sub refuses');
refuses('my @a = (0); my $f = sub { $a[0] ||= 3 }; $f->(); print "@a\n";',
    qr/GAP: `\|\|=` into an element of an aggregate an anon sub closes over/,
    'an element of a captured array in an anon sub refuses');
refuses('my %h; my $f = sub { $h{$_[0]}{x} //= $_[1] }; my @r = ($f->("a", 1), $f->("a", 2)); print "@r\n";',
    qr/GAP: `\/\/=` into an element of an aggregate an anon sub closes over/,
    'a nested element of a captured hash in an anon sub refuses');
refuses('my %h; my $f = sub { $h{a}[0] ||= $_[0] }; my @r = ($f->(1), $f->(2)); print "@r\n";',
    qr/GAP: `\|\|=` into an element of an aggregate an anon sub closes over/,
    'a hash-of-array element of a captured hash refuses');
refuses('my @a; my $f = sub { $a[0][0] ||= $_[0] }; my @r = ($f->(3), $f->(4)); print "@r\n";',
    qr/GAP: `\|\|=` into an element of an aggregate an anon sub closes over/,
    'an array-of-array element of a captured array refuses');
refuses('my @a; my $f = sub { $a[0]{x} //= $_[0]; $a[0]{x} }; my @r = ($f->(1), $f->(2)); print "@r\n";',
    qr/GAP: `\/\/=` into an element of an aggregate an anon sub closes over/,
    'an array-of-hash element of a captured array refuses');

# THE RESULT IS THE TARGET ITSELF, not a copy of its value: `++`, `\`, a sub
# argument and `+=` all write through it. The op says so with OPf_MOD.
refuses('my %h; my $r = ($h{a} //= 0)++; print "$r $h{a}\n";',
    qr/GAP: `\/\/=` whose result is itself modified/,
    'an incremented element //= refuses');
refuses('my %h; for my $k (qw(a a b)) { ($h{$k} //= 0)++ } print join(",", map {"$_=$h{$_}"} sort keys %h), "\n";',
    qr/GAP: `\/\/=` whose result is itself modified/,
    'an incremented element //= in a loop refuses');
refuses('my %h; print join(" ", grep { !($h{$_} //= 0)++ } qw(a b a c b)), "\n";',
    qr/GAP: `\/\/=` whose result is itself modified/,
    'the seen-hash idiom over //= in a grep refuses');
refuses('my %h; my $r = \($h{a} //= 1); $$r = 9; print "$h{a}\n";',
    qr/GAP: `\/\/=` whose result is itself modified/,
    'a reference to an element //= refuses');
refuses('my %h; sub bump { $_[0]++ } bump($h{a} //= 4); print "$h{a}\n";',
    qr/GAP: `\/\/=` whose result is itself modified/,
    'an element //= passed to a sub refuses');
refuses('my @a; sub inc { $_[0] += 10 } inc($a[0] //= 1); print "$a[0]\n";',
    qr/GAP: `\/\/=` whose result is itself modified/,
    'an array element //= passed to a sub refuses');
refuses('my $x; ($x //= 1) += 2; print "$x\n";',
    qr/GAP: `\/\/=` whose result is itself modified/,
    'a lexical //= whose result is added to refuses');
refuses('my $x = 0; my $r = \($x ||= 5); $$r = 9; print "$x\n";',
    qr/GAP: `\|\|=` whose result is itself modified/,
    'a reference to a lexical ||= refuses');
round_trips(<<'SRC', 'an element //= whose result is only read');
my %h; my $v = $h{a} //= 3; print(($h{b} ||= 7), " $v $h{a}\n");
my @l = (($h{c} //= 1), ($h{c} //= 2)); print "@l\n";
SRC

# AN ELEMENT OF @_ ALIASES THE CALLER'S ARGUMENT, and the caller's graph does
# not see a write the callee makes through it.
refuses('sub f { $_[0] ||= 5; return } my @w = (0); f($w[0]); print "@w\n";',
    qr/GAP: `\|\|=` into an element of \@_, which aliases the caller's argument/,
    '||= into $_[0] refuses');
refuses('sub f { $_[0] //= 5; return } my @w = (undef); f($w[0]); print "@w\n";',
    qr/GAP: `\/\/=` into an element of \@_, which aliases the caller's argument/,
    '//= into $_[0] refuses');
refuses('sub f { $_[1] &&= 5; return } my @w = (1, 1); f(@w); print "@w\n";',
    qr/GAP: `&&=` into an element of \@_, which aliases the caller's argument/,
    '&&= into $_[1] refuses');

# AN ELEMENT WRITE INVALIDATES AN ARRAY'S LITERAL INITIALISER. `"@l"` reads
# the literal's own values until something writes the array; `++` and `+=`
# into an element did not say so, and the interpolation printed the old ones.
round_trips(<<'SRC', 'increments and compound stores into an initialised array');
my %h; my @l = (($h{a} //= 1), ($h{a} //= 2)); $l[0]++; print "@l $h{a}\n";
my @m = (1, 1); ++$m[1]; my @n = (1, 1); $n[0] += 4; my @o = (3, 3); $o[1]--;
my @p = (1, 2); my $i = 1; $p[$i] *= 5; my %q = (a => 1); $q{a}++;
print "@m @n @o @p $q{a}\n";
SRC
refuses('my $v=0; my $r = \$v; $$r //= 4; print "$v\n";',
    qr/GAP: `\/\/=` into something other than a lexical scalar or an element/,
    '//= through a scalar ref refuses');
refuses('sub f { my %h; $h{a} //= return 5; 7 } print f(), "\n";',
    qr/GAP: `\/\/=` whose right side leaves or yields no single value/,
    'a right side that returns refuses');
refuses('my %h; for my $i (1, 2) { $h{a} //= next } print "x\n";',
    qr/GAP: a loop control \(`next`\) inside a branch arm is not yet lowered/,
    'a right side that leaves the loop refuses');
refuses('my $h; $h->{x}{y} //= 1; print ref($h), "\n";',
    qr/GAP: `\/\/=` into an element of undef, which perl would autovivify/,
    'an element of an undefined lexical, which would autovivify, refuses');

# A SLICE IN SCALAR CONTEXT IS ONE SCALAR. Stored into a scalar inside a loop,
# its List stamp reached the loop-carried Phi, which then joined to List and
# was emitted as an array: `$x ||= (...)[1]` printed the array's count.
round_trips(<<'SRC', '||= of a list slice whose operand has an effect, in a loop');
my $x = 0; my $s = ""; for my $i (1..3) { $x ||= ($s .= $i, $i > 1 ? $i : 0)[1] } print "$x $s\n";
SRC
round_trips(<<'SRC', 'a list slice stored into a scalar in a foreach');
my $x = 0; for my $i (1..3) { $x = (7, $i)[1] } print "$x\n";
SRC
round_trips(<<'SRC', 'a list slice stored into a scalar in a while, and in an arm');
my $x = 0; my $i = 0; while ($i < 3) { $i++; $x = (7, $i)[1] }
my $y = 0; for my $j (1..3) { if ($j > 1) { $y = (7, $j)[1] } } print "$x $y\n";
SRC
round_trips(<<'SRC', 'an array and a hash slice stored into a scalar in a loop');
my @a = (4,5,6); my %h = (a=>4, b=>5); my ($x, $y) = (0, 0);
for my $i (1..3) { $x = @a[0,$i-1] } for my $k (qw(a b)) { $y = @h{"a",$k} } print "$x $y\n";
SRC
round_trips(<<'SRC', 'a slice of a sort, into a scalar in a loop; and in list context');
my $x = 0; my @r; for my $i (1..3) { $x = (sort { $b <=> $a } 1..$i)[0]; push @r, (7, $i)[1] } print "$x @r\n";
SRC

# A KEY/VALUE SLICE HAS NO IR SPELLING. `%h{...}` and `%a[...]` yield pairs,
# and Slice says only "values": it was emitted as `@h{...}`, which drops keys.
refuses('my %h; my @k = qw(a b); for (@k) { $h{$_} //= length } print join(",", %h{sort keys %h}), "\n";',
    qr/GAP: a key\/value slice \(kvhslice\) is not yet lowered/,
    'a key/value hash slice refuses');
refuses('my @a = (5,6); print join(",", %a[0,1]), "\n";',
    qr/GAP: a key\/value slice \(kvaslice\) is not yet lowered/,
    'a key/value array slice refuses');

done_testing;
