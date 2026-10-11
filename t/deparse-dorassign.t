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

# STILL REFUSED.
refuses('my $v=0; my $r = \$v; $$r //= 4; print "$v\n";',
    qr/GAP: `\/\/=` into something other than a lexical scalar or an element/,
    '//= through a scalar ref refuses');
refuses('sub f { my %h; $h{a} //= return 5; 7 } print f(), "\n";',
    qr/GAP: `\/\/=` whose right side leaves or yields no single value/,
    'a right side that returns refuses');
refuses('my %h; for my $i (1, 2) { $h{a} //= next } print "x\n";',
    qr/GAP: a loop control \(`next`\) inside a branch arm is not yet lowered/,
    'a right side that leaves the loop refuses');

done_testing;
