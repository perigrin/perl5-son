# ABOUTME: A sort comparator block perl nulled from a leave -- one that calls a sub or
# ABOUTME: declares a `my` -- round-trips, or refuses by name where it cannot yet.

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

# A REFUSAL NAMES ITS CAUSE: the producer's skip or the renderer's gap must
# say why, so a refusal that moves to another cause fails here.
sub refuses ($src, $why, $name) {
    my $data = graph_of($src);
    my $err  = producer_stderr();
    my $d    = SoN::Deparse->new;
    my $out  = $data ? $d->render($data) : undef;
    ok !defined $out, "$name: refuses" or diag $out;
    like $err . ($d->gap // ''), $why, "$name: names its cause";
}

# THE CLUSTER: every chalk comparator that refused is an inline block calling
# a method, and a block that calls a sub or declares a `my` gets a real leave
# that the optimizer nulls. It took the runtime-comparator refusal.
my @cases = (
    [ q{package O{sub new{bless {i=>$_[1]}} sub id{$_[0]{i}}} my @o=map {O->new($_)} qw(b a c); print join(",", map {$_->id} sort { $a->id cmp $b->id } @o),"\n";},
      'a block calling a method' ],
    [ q{sub f{length $_[0]} print join(",", sort { f($a) <=> f($b) or $a cmp $b } qw(ccc a bb aa)),"\n";},
      'a block calling a sub' ],
    [ q{print join(",", sort { my $x=$a; my $y=$b; $y <=> $x } 3,1,2),"\n";},
      'a block declaring a my' ],
    [ q{package P; sub f { join ",", sort { my $t = lc($b); $t cmp lc($a) } @_ } package main; print P::f(qw(a C b)),"\n";},
      'a block in package P' ],

    # A SORT ALIASES ITS ARGUMENTS, so perl flags each OPf_MOD; they are reads.
    [ q{my $k = 5; print join(",", sort { my $x=$a; $x <=> $b } 3,$k), "\n";},
      'a lexical scalar argument keeps its binding' ],
    [ q{sub byd { $b <=> $a } my $k = 5; print join(",", sort byd 3,$k), "\n";},
      'the same with a named comparator' ],
    [ q{my $k=5; my @r = sort { my $t=$a; $t <=> $b } 3, scalar($k); print "@r\n";},
      'a scalar() argument' ],
    [ q{my @r; for my $i (1,2) { @r = sort { my $x=$a; $x <=> $b } 3,1,2,$i; print "@r\n" }},
      'a foreach variable argument in a loop' ],
    [ q{my @a=(4); my @r = sort { my $t=$a; $t <=> $b } $a[0], 2; $a[0]++; print "@r|$a[0]\n";},
      'an element argument is not a compound-assign target' ],
    [ q{my %h=(k=>4); my @r = sort { my $t=$a; $t <=> $b } $h{k}, 2; $h{k}++; print "@r|$h{k}\n";},
      'a hash element argument' ],
    [ q{sub f { my @r = sort { my $t=$a; $t <=> $b } $_[0], 2; "@r" } print f(5), "\n";},
      'an @_ element argument' ],

    # A COMPARATOR SORT RUNS CODE, so it runs where it is, once.
    [ q{my @a=(4); my $z = $a[0]; my @r = sort { my $t=$a; $t <=> $b } $a[0], 2; $a[0] = 1; print "@r|$z\n";},
      'an element read before the sort and stored after it' ],
    [ q{sub c {$a<=>$b} my @a=(4); my $z = $a[0]; my @r = sort c $a[0], 2; $a[0] = 1; print "@r|$z\n";},
      'the same with a named comparator' ],
    [ q{our $n=0; sub cn {$n++; $a<=>$b} my @r = sort cn 3,1,2; print "$n\n";},
      'a counting comparator whose list is assigned but unread' ],
    [ q{our $n=0; my @r = sort { $n++; my $t=$a; $t <=> $b } 3,1,2; print "$n @r\n";},
      'a counting block' ],
    [ q{my @r = sort { print "x"; my $t=$a; $t<=>$b } 3,1; print "\n";},
      'a printing block' ],
    [ q{my $c = 1; my @r = $c ? (sort { my $t=$a; $t <=> $b } 3,1,2) : (); print "@r\n";},
      'a block sort in a ternary arm' ],
    [ q{my $c = 1; my @r = ($c && sort { my $t=$a; $t <=> $b } 3,1,2); print "@r\n";},
      'a block sort on the right of &&' ],

    # A VOID SORT IS SKIPPED, so its comparator never runs.
    [ q{our $n = 0; sub cn { $n++; $a <=> $b } sort cn 3, 1, 2; my @r = sort cn 3, 1, 2; print "$n @r\n";},
      'a void named sort beside a list one' ],
    [ q{our $n = 0; sort { $n++; my $t=$a; $t <=> $b } 3, 1, 2; print "$n\n";},
      'a void block sort' ],

    # AN EVAL'S CONTEXT IS ITS OWN: a list eval yields the whole sort.
    [ q{my @r = eval { sort { die "boom\n" if $a == 2; $a <=> $b } 3,1,2 }; print "[@r] $@";},
      'a dying block in a list eval' ],
    [ q{my @r = eval { sort { my $t=$a; $t <=> $b } 3,1,2 }; print "[@r]\n";},
      'a block sort in a list eval' ],
    [ q{my @r = eval { sort { $b <=> $a } 3,1,2 }; print "[@r]\n";},
      'a folded sort in a list eval' ],
    [ q{my @a = (5,0); my $x = eval { @a[0,1] }; print "$x\n";},
      'a scalar eval of a slice is its last element' ],
    [ q{sub f {(5,0)} my $x = eval { f() }; print "$x\n";},
      'a scalar eval of a list-returning call' ],

    # A SORT'S OPf_STACKED NAMES ITS COMPARATOR, not a destination: a scalar
    # left on the stack by an earlier statement is not a store target.
    [ q{our $c = 7; my $before = $c; my @r = sort { my $t=$a; $t <=> $b } 3,1,2; print "$before|@r\n";},
      'a package read bound before a block sort' ],
    [ q{our $c = 7; my $before = $c; my @r = sort { my $t=$a; $t <=> $b } 3,1,2; print "@r|$c\n";},
      'the package scalar is not overwritten' ],
    [ q{our $c = 7; my $before = $c; my @r = sort { my $t=$a; $t <=> $b } 3,1,2; $c = 9; print "$c|@r|$before\n";},
      'a later store to the package scalar' ],
    [ q{our $c = 7; sub s1 { my $before = $c; my @r = sort { my $t=$a; $t <=> $b } @_; "$before|@r" } print s1(3,1,2), "\n";},
      'the same inside a sub' ],
    [ q{our $c=7; sub cc {$a<=>$b} my $before=$c; my @r = sort cc 3,1,2; print "$before|@r\n";},
      'the same with a named comparator' ],

    # A CALL MAY WRITE ANY PACKAGE SCALAR, so a read before it is spelled
    # before it.
    [ q{our $n = 0; sub cn { $n++; $a <=> $b } my $m = $n; print "$m|", sort(cn 3,1), "\n";},
      'a package read bound before a counting sort' ],
    [ q{our $n = 0; sub cn { $n++; $a <=> $b } print "$n|", sort(cn 3,1), "\n";},
      'a package read in the same list as a counting sort' ],
    [ q{our $n = 0; sub g { $n++; 5 } my $m = $n; print "$m|", g(), "\n";},
      'a package read bound before an ordinary call' ],
    [ q{our $n; sub g { $n = 3; 5 } my $m = $n // 0; print "$m|", g(), "|$n\n";},
      'a package read at entry before a call' ],
    [ q{our $c = 0; sub f { $c++; $_[0] } my @r = sort { f($a) <=> f($b) } 3,1,2; my $d = $c; my @s = sort { f($a) <=> f($b) } 5,4; print "@r $d $c @s\n";},
      'a read between two sub-calling block sorts' ],
    [ q{our $c = 0; sub f { $c++; $_[0] } my $before = $c; my @r = sort { f($a) <=> f($b) } 3,1,2; print "$before @r $c\n";},
      'a read before a sub-calling block sort' ],
    [ q{our $n = 0; sub g { $n++; 5 } my $m = $n; if ($m == 0) { g() } print "$m|$n\n";},
      'a package read before a call in a branch arm' ],
    [ q{our $s = "a"; sub g { $s .= "b" } my $t = $s; g(); print "$t $s\n";},
      'a package string read before a call that appends to it' ],
    [ q{our $n=0; package O; sub b { $main::n++ } package main; my $m = $n; O->b; print "$m $n\n";},
      'a package read before a method call' ],
    # ...but a read whose version is a call inside an eval is not bound at
    # that call: a call that dies skips the binding.
    [ q{sub d { die "e1\n" } sub g { 1 } print eval { d(); 1 } ? "ran\n" : $@; g();},
      'a $@ read after an eval whose call died' ],
    [ q{our $n = 0; sub d { $n = 3; die "x\n" } sub g { $n = 7 } print eval { d(); 1 } ? "ran\n" : "$n\n"; g();},
      'a package read after an eval whose call wrote it and died' ],
    [ q{our $n = 1; sub bump { $_[0]++ } bump($n); bump($n); print "$n\n";},
      'a package scalar handed to a call is still aliased' ],

    # AN IN-PLACE SORT is an assign perl folded into the sort.
    [ q{my @a = (3,1,2); @a = sort { my $t=$a; $t <=> $b } @a; print "@a\n";},
      'an in-place block sort' ],
    [ q{my @x=(3,1,2); @x = sort { $b <=> $a } @x; print "@x\n";},
      'an in-place folded sort' ],
    [ q{sub c {$a<=>$b} my @a=(3,1,2); @a = sort c @a; print "@a\n";},
      'an in-place named sort' ],
    [ q{sub f { my @a = @_; @a = sort { my $t=$a; $t <=> $b } @a; "@a" } print f(3,1,2), "\n";},
      'an in-place sort in a sub' ],
    [ q{my @a=(3,1,2); for my $i (1,2) { @a = sort { $a <=> $b } @a; } print "@a\n";},
      'an in-place sort in a loop' ],

    [ q{my @x=(3,1,2); print scalar(my @y = sort { my $t=$a; $t <=> $b } @x), "\n";},
      'a counted list assign of a block sort' ],
    [ q{my %seen; for my $i (3, 1, 2) { %seen = map { $_ => 1 } sort { my $t = $a; $t <=> $b } keys(%seen), $i; } print join(",", sort keys %seen), "\n";},
      'a hash rebuilt in a loop from a block sort of its keys' ],
);
round_trips(@$_) for @cases;

my $local = qr/GAP: a sort comparator block that localises a variable/;
refuses(q{our $x=5; print join(",", sort { local $x = $a; $x <=> $b } 3,1,2), " $x\n";},
    $local, 'a block localising a scalar');
refuses(q{our @s; print join(",", sort { local @s = ($a); $a <=> $b } 3,1,2), "\n";},
    $local, 'a block localising an array');
refuses(q{our %h; print join(",", sort { local $h{k} = $a; $a <=> $b } 3,1,2), "\n";},
    $local, 'a block localising an element');
refuses(q{my $n = 0; my @r = sort { $n++; my $t=$a; $t <=> $b } 3,1,2; print "$n @r\n";},
    qr/GAP: a sort comparator block that writes a lexical of its enclosing scope \(\$n\)/,
    'a block writing an outer lexical');
refuses(q{my @k=(3,1,2); print join(",", sort { my $t=$a; $k[$t] <=> $k[$b] } 0,1,2), "\n";},
    qr/GAP: a sort comparator block that reads a lexical of its enclosing scope \(\@k\)/,
    'a block reading an outer lexical');
refuses(q{for (1,-1) { print join(",", sort { $_*($a <=> $b) } 3,1,2),"\n" }},
    qr/GAP: a sort comparator block that reads \$_/, 'a block reading $_');

my $inplace = qr/GAP: an in-place sort of an array other than a plain lexical/;
refuses(q{our @a = (3,1,2); @a = sort { my $t=$a; $t <=> $b } @a; print "@a\n";},
    $inplace, 'an in-place sort of a package array');
refuses(q{my @a=(3,1,2); my $r=\@a; @a = sort { $a <=> $b } @a; print "@$r\n";},
    $inplace, 'an in-place sort of a referenced array');
refuses(q{my @a=(3,1,2); my $c = sub { "@a" }; @a = sort { $a <=> $b } @a; print $c->(), "\n";},
    $inplace, 'an in-place sort of a captured array');

my $destructure = qr/GAP: a list assign that destructures a block eval's value/;
refuses(q{my ($x, $y) = eval { sort { my $q=$a; $q <=> $b } 3,1,2 }; print "$x $y\n";},
    $destructure, 'two targets from an eval of a block sort');
refuses(q{my ($x) = eval { sort { my $q=$a; $q <=> $b } 3,1,2 }; print "$x\n";},
    $destructure, 'one target from an eval of a block sort');
refuses(q{my ($x, @y) = eval { sort { my $q=$a; $q <=> $b } 3,1,2 }; print "$x @y\n";},
    $destructure, 'a scalar and an array from an eval of a block sort');
refuses(q{my ($x, $y) = eval { (5,6) }; print "$x $y\n";},
    $destructure, 'two targets from an eval of a list');
round_trips(q{my ($x) = eval { 4 }; print "$x\n";}, 'one target from a scalar eval');

my $runtime = qr/GAP: a sort comparator chosen at runtime/;
refuses(q{my $c=sub{$b<=>$a}; print join(",", sort $c 3,1,2),"\n";},
    $runtime, 'a lexical subref comparator');
refuses(q{our $c; $c = sub {$b<=>$a}; print join(",", sort $c 3,1,2),"\n";},
    $runtime, 'a package subref comparator');
refuses(q{my $nm="byd"; sub byd {$b<=>$a} print join(",", sort $nm 3,1,2),"\n";},
    $runtime, 'a sub name held in a variable');

# DIFF BEFORE A COMPARATOR BLOCK COULD LOWER, with no comparator in the cause.
# Each renders and runs; only the answer is wrong, so only that is TODO.
sub still_wrong ($src, $why) {
    my $data = graph_of($src) or return fail "$why: translates";
    my $out  = SoN::Deparse->new->render($data) // return fail "$why: renders";
    my $todo = todo $why;
    is run_perl($out), run_perl($src), $why;
}
still_wrong(q{my $n = 0; my @r = eval { $n++; reverse 3,1,2 }; print "@r $n\n";},
    'a lexical store inside a block eval is dropped');
still_wrong(q{my @r = eval { 1 ? (1,2) : (3) }; print "@r\n";},
    'a list eval of a ternary keeps only its last element');
still_wrong(q{my $r = []; my $n = (@$r = (4,5,6)); print "$n @$r\n";},
    'a counted list assign through an array deref loses elements');

done_testing;
