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
    # An aggregate assigned from a list eval is placed after the eval.
    [ q{sub w { my @r = eval { sort { my $q=$a; $q <=> $b } 3,1,2 }; @r } my @r = w(); print "@r\n";},
      'an array from a list eval returned implicitly' ],
    [ q{sub w { my @r = eval { reverse 3,1,2 }; @r } my @r = w(); print "@r\n";},
      'the same over reverse' ],
    [ q{sub w { my @r = eval { reverse 3,1,2 }; push @r, 0; @r } my @r = w(); print "@r\n";},
      'the same with a push' ],
    [ q{sub w { my @r = eval { die "x\n"; (1) }; scalar(@r) . $@ } print w();},
      'a list eval that dies yields the empty list' ],
    [ q{my @r = eval { die "x\n"; (1) }; print scalar(@r) . $@;},
      'the same at the top level' ],

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

    # A READ AFTER A MERGE OR A LOOP: its version is a Phi, or the loop
    # body's last call, and a walk from there never reached what follows.
    [ q{package O; our $calls = 0; sub new { bless {v=>$_[1]}, $_[0] } sub v { $calls++; $_[0]{v} } package main; my @o = map { O->new($_) } 3,1; my $before = $O::calls; my @s = sort { $a->v <=> $b->v } @o; print "$before $O::calls\n";},
      'a package read after a map loop of calls, before a method-calling sort' ],
    [ q{our $n=0; if (@ARGV) {$n=3} my $m=$n; my @r = sort { my $t=$a; $n++; $t <=> $b } 3,1; print "$m $n\n";},
      'a package read after a branch, before a counting block sort' ],
    [ q{our $n=0; sub h{1} sub g{$n=5} my @o = map { h($_) } 3,1; my $m = $n; g(); print "$m $n\n";},
      'a package read after a map loop of calls, before a call' ],
    [ q{our $n=0; sub h{1} sub g{$n=5} if (@ARGV) { h() } my $m = $n; g(); print "$m $n\n";},
      'a package read after a call in an arm' ],
    [ q{our $n=0; sub h{1} sub g{$n=5} if (@ARGV) { h() } else { $n = 1 } my $m = $n; g(); print "$m $n\n";},
      'a package read after an if/else' ],
    [ q{our $n=0; sub h{1} sub g{$n=5} for (1,2) { h() } my $m = $n; g(); print "$m $n\n";},
      'a package read after a foreach of calls' ],
    [ q{our $n=0; sub h{1} sub g{$n=5} my $i=0; while ($i++ < 2) { h() } my $m = $n; g(); print "$m $n\n";},
      'a package read after a while of calls' ],
    [ q{our $n=0; sub h{$n+=2} for my $i (1,2) { for my $j (1,2) { h() } } my $m = $n; $n = 7; print "$m $n\n";},
      'a package read after nested loops, before a store' ],
    [ q{our $n=0; if (@ARGV) { $n = 1 } my $m = $n; $n = 2; print "$m $n\n";},
      'a package read after a store in an untaken arm' ],
    [ q{our $n=0; sub h{$n++} if (!@ARGV) { h() } my $m = $n; $n = 9; print "$m $n\n";},
      'a package read after a call in a taken arm' ],
    [ q{our $n=0; if (@ARGV) { $n = 1 } my $m = $n; $n = 2; my $q = $n; $n = 3; print "$m $q $n\n";},
      'a read bound at a join beside one bound at a store' ],
    [ q{our $n=0; sub g{$n=5} sub f { if ($_[0]) { $n = 1 } my $m = $n; g(); "$m $n" } print f(0), "|", f(1), "\n";},
      'a package read after a branch, inside a sub' ],
    [ q{our $n=0; sub g{$n=5} for my $i (1,2) { if ($i == 2) { $n = $i } } my $m = $n; g(); print "$m $n\n";},
      'a package read after a branch inside a loop' ],
    [ q{our $n=0; sub g{$n=5} eval { $n = 2; die "x\n" }; my $m = $n; g(); print "$m $n\n";},
      'a package read after an eval that died' ],

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
    # ...and the array is still a container afterwards: bound to the sort
    # itself, each of these was spelled on `sort(...)`, a list value.
    [ q{my @a = (1,2); @a = sort @a; push @a, 3; print "@a\n";},
      'a push after an in-place sort' ],
    [ q{my @a = (2,1); @a = sort @a; shift @a; print "@a\n";},
      'a shift after an in-place sort' ],
    [ q{my @a = (3,1,2); @a = sort @a; my @b = splice(@a, 0, 1); print "@a|@b\n";},
      'a splice after an in-place sort' ],
    [ q{my @a = (1,2); @a = sort { $a <=> $b } @a; $a[0] = 9; print "@a\n";},
      'an element store after an in-place folded sort' ],
    [ q{my @a = (2,1); @a = sort @a; for (@a) { $_++ } print "@a\n";},
      'a foreach alias after an in-place sort' ],
    [ q{my @a = (2,1); @a = sort @a; my $r = \@a; push @$r, 7; print "@a ", scalar(@$r), "\n";},
      'a reference taken after an in-place sort' ],
    [ q{my @a = (3,1); for my $i (1..3) { push @a, $i; @a = sort { $a <=> $b } @a; } print "@a\n";},
      'a push and an in-place sort in a loop' ],
    [ q{sub f { my @a = @_; @a = sort { my $t=$a; $t <=> $b } @a; push @a, 9; shift @a; "@a" } print f(3,1,2), "\n";},
      'a push and a shift after an in-place block sort in a sub' ],

    # ...and in a branch arm the merge is an array, not its count.
    [ q{my @a = (3,1,2); if (!@ARGV) { @a = sort { my $t=$a; $t <=> $b } @a } print "@a\n";},
      'an in-place block sort in an arm' ],
    [ q{my @a = (3,1,2); if (!@ARGV) { @a = sort { my $t=$a; $t <=> $b } @a } else { @a = (9) } print "@a\n";},
      'an in-place block sort in one arm of two' ],
    [ q{sub c { $a <=> $b } my @a = (3,1,2); if (!@ARGV) { @a = sort c @a } print "@a\n";},
      'an in-place named sort in an arm' ],
    [ q{my @a = (3,1,2); if (!@ARGV) { @a = sort @a; push @a, 0 } print "@a\n";},
      'an in-place sort and a push in an arm' ],
    [ q{my %h = (a=>1); if (!@ARGV) { %h = map { $_ => 2 } sort { my $t=$a; $t cmp $b } keys %h } print join(",", %h), "\n";},
      'a hash rebuilt from a block sort in an arm' ],
    [ q{my @r; if (@ARGV) { @r = (1) } else { @r = eval { sort { my $q=$a; $q<=>$b } 2,1 } } print "@r\n";},
      'an eval of a block sort assigned in one arm of two' ],
    [ q{my @r; if (@ARGV) { @r = (1) } else { @r = eval { sort 2,1 } } print "@r\n";},
      'an eval of a plain sort assigned in one arm of two' ],

    # A LIST-CONTEXT SORT ON THE RIGHT OF && is pinned in the arm the && takes.
    [ q{sub c { $a <=> $b } my @r = @ARGV && sort c 3,1,2; print scalar(@r), "\n";},
      'a named sort on the right of an untaken &&' ],
    [ q{my @r = @ARGV && sort { my $t=$a; $t <=> $b } 3,1,2; print scalar(@r), "\n";},
      'a block sort on the right of an untaken &&' ],
    [ q{my @r = !@ARGV && sort { my $t=$a; $t <=> $b } 3,1,2; print "@r\n";},
      'a block sort on the right of a taken &&' ],
    [ q{sub c { $a <=> $b } my @r = @ARGV || sort c 3,1,2; print "@r\n";},
      'a named sort on the right of ||' ],
    [ q{sub c { $a <=> $b } my @r; @r = @ARGV && sort c 3,1,2; print scalar(@r), "\n";},
      'a named sort on the right of && assigned to a declared array' ],
    [ q{sub f {(1,2)} sub g { my @r = $_[0] && f(); scalar(@r) } print g(0), g(1), "\n";},
      'a list call on the right of && in a sub' ],
    # ...and two targets take what perl distributes at runtime.
    [ q{my ($x,$y) = !@ARGV && sort { my $t=$a; $t <=> $b } 2,1; print "$x $y\n";},
      'two targets from a block sort on the right of &&' ],
    [ q{my ($x,$y) = !@ARGV && reverse 2,1; print "$x $y\n";},
      'two targets from reverse on the right of &&' ],
    [ q{sub f {(1,2)} my ($x,$y) = @ARGV && f(); print defined $x ? 1 : 0, defined $y ? 1 : 0, "\n";},
      'two targets from an untaken &&' ],
    [ q{my ($x,$y) = !@ARGV ? (sort { my $t=$a; $t <=> $b } 2,1) : (); print "$x $y\n";},
      'two targets from a block sort in a ternary arm' ],
    [ q{sub f {(1,2)} my ($x,$y) = @ARGV ? f() : (3); print "$x ", $y // "u", "\n";},
      'two targets from a ternary of a call and a one-element list' ],
    [ q{my $k = 3; my ($x) = $k && 7; print "$x\n";},
      'one target from a scalar &&' ],

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
# ...and one of a comma list refuses earlier, in the producer.
my $leaves = qr/GAP: a block eval in list or caller context whose body leaves a list/;
refuses(q{my ($x, $y) = eval { sort { my $q=$a; $q <=> $b } 3,1,2 }; print "$x $y\n";},
    $destructure, 'two targets from an eval of a block sort');
refuses(q{my ($x) = eval { sort { my $q=$a; $q <=> $b } 3,1,2 }; print "$x\n";},
    $destructure, 'one target from an eval of a block sort');
refuses(q{my ($x, @y) = eval { sort { my $q=$a; $q <=> $b } 3,1,2 }; print "$x @y\n";},
    $destructure, 'a scalar and an array from an eval of a block sort');
refuses(q{my ($x, $y) = eval { (5,6) }; print "$x $y\n";},
    $leaves, 'two targets from an eval of a list');
round_trips(q{my ($x) = eval { 4 }; print "$x\n";}, 'one target from a scalar eval');

my $callers = qr/GAP: a block eval whose value goes back in its caller's context/;
refuses(q{sub w { return eval { sort { my $q=$a; $q <=> $b } 3,1,2 } } my @r = w(); my $s = w(); print "@r|", defined $s ? "d" : "u", "\n";},
    $callers, 'a returned eval of a block sort');
refuses(q{sub w { eval { sort { my $q=$a; $q <=> $b } 3,1,2 } } my @r = w(); print "@r\n";},
    $callers, 'an eval of a block sort as the last statement');
refuses(q{sub cn {$a<=>$b} sub w { return eval { sort cn 3,1,2 } } my @r = w(); print "@r\n";},
    $callers, 'a returned eval of a named sort');
refuses(q{sub w { return eval { sort { $a <=> $b } 3,1,2 } } my @r = w(); print "@r\n";},
    $callers, 'a returned eval of a folded sort');
# A body whose value is its last statement is emitted as that statement,
# so it falls off the end in the caller's context and needs no binding.
# A SCALAR VALUE returned from an eval reads the caller's context at the
# return: () to a list caller when the body died, undef to a scalar one.
round_trips(q{sub w { return eval { 5 } } my $s = w(); print "$s\n";},
    'a returned eval of a constant');
round_trips(q{sub w { eval { $_[0]*2 } } my $s = w(4); my @r = w(3); print "$s @r\n";},
    'an eval of arithmetic as the last statement');
round_trips(q{my $x = 3; sub w { return eval { $x + 1 } } print w(), "\n";},
    'a returned eval reading a lexical');
round_trips(q{sub w { eval { 5 } } my @r = w(); my $s = w(); print "@r $s\n";},
    'an eval as the last statement, called both ways');
round_trips(q{sub w { return eval { die "x\n" if $_[0]; 5 } } my @r = w(1); my $s = w(1); print scalar(@r), " ", defined $s ? "d" : "u", " ", w(0), "\n";},
    'a returned eval that may die, called both ways');
refuses(q{sub w { eval { (1,2) } } my @r = w(); my $s = w(); print "@r $s\n";},
    $leaves, 'an eval of a comma list as the last statement');
refuses(q{my @r; if (@ARGV) { @r = (1) } else { @r = eval { (2,1) } } print "@r\n";},
    $leaves, 'an eval of a list assigned in one arm of two');
refuses(q{my @r = eval { 1 ? (1,2) : (3) }; print "@r\n";},
    $leaves, 'a list eval of a ternary');
refuses(q{my %h = eval { (a=>1) }; print join(",", %h), "\n";},
    $leaves, 'a list eval of a list');
round_trips(q{my $x = eval { (1,2) }; print "$x\n";},
    'a scalar eval of a list is its last element');
# A WHOLE ASSIGN IN AN ARM merges as the array, whatever follows it there.
round_trips(q{my @a = (3,1); if (@a) { @a = (1,3); $a[1] = 7 } print "@a\n";},
    'a whole assign and an element store in one arm');
round_trips(q{my %h = (a=>1); if (!@ARGV) { %h = (b=>2) } print join(",", %h), "\n";},
    'a whole hash assign in one arm');
refuses(q{sub w { eval { @_ } } my @r = w(4,5); my $s = w(4,5); print "@r $s\n";},
    $callers, 'an eval of an array as the last statement');
refuses(q{sub f { (7,8) } sub w { eval { f() } } my @r = w(); my $s = w(); print "@r $s\n";},
    $callers, 'an eval of a call as the last statement');
round_trips(q{sub w { return eval { die "x\n" } } my @r = w(); print scalar(@r), "\n";},
    'a returned eval that dies');
round_trips(q{sub w { my $x = eval { 5 }; $x } print w(), "\n";},
    'a scalar eval inside a sub');
round_trips(q{sub w { eval { 1 } or return 0; 2 } print w(), "\n";},
    'a boolean eval inside a sub');

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
refuses(q{my $n = 0; my @r = eval { $n++; reverse 3,1,2 }; print "@r $n\n";},
    qr/GAP: a block eval that rebinds a lexical declared outside it/,
    'a lexical store inside a block eval');
still_wrong(q{our $n=0; sub h{$n+=2} for (1,2) { $n++; h() } my $m = $n; $n = 7; print "$m $n\n";},
    'a package scalar stored in a loop body is carried past a call that writes it');
still_wrong(q{my $r = []; my $n = (@$r = (4,5,6)); print "$n @$r\n";},
    'a counted list assign through an array deref loses elements');

done_testing;
