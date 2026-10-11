# ABOUTME: A ternary whose arm stores an element yields the stored value when it is a
# ABOUTME: constant, in WANT 0 as well; any other stored value, local or lvalue use refuses.

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

# Only the output: under a todo, the stderr check would pass and count as
# an unexpected success.
sub output_matches ($src, $name) {
    my $out = SoN::Deparse->new->render(graph_of($src) // {}) // return fail "$name: renders";
    is run_perl($out), run_perl($src), $name;
}

sub refuses ($src, $cause, $name) {
    graph_of($src);
    like producer_stderr(), $cause, "$name: refused, naming its cause";
}

my $not_const = qr/GAP: a consumed ternary arm stores an element and yields a value that is not a constant/;
my $key_mem   = qr/GAP: a consumed ternary arm stores an element whose key reads memory or has an effect/;

# A constant stored value merges, in scalar, list and the caller's context.
# WANT 0 is the caller's context: taken for void, the value was dropped and
# the sub returned its last array (07|08) or nothing (`return ();`).
round_trips(q{my @a = (0); my $c = 1; my $x = $c ? ($a[0] = 7) : ($a[0] = 8); print "$x $a[0]\n";},
    'scalar context, both arms store');
round_trips(q{sub f { my @a = (0); $_[0] ? ($a[1] = 7) : ($a[1] = 8) } print f(1), "|", f(0), "\n";},
    'the last statement of a sub');
round_trips(q{sub f { my @a = (0); return $_[0] ? ($a[0] = 7) : 8 } print f(1), f(0), "\n";},
    'under return');
round_trips(q{my @a=(0); sub f { return $_[0] ? ($a[0]=7) : ($a[1]=8) } print f(1), f(0), " @a\n";},
    'under return, an outer array');
round_trips(q{my @a = (0); sub f { $_[0] ? ($a[0] = 7) : ($a[0] = 8) } for my $c (1,0) { my @l = f($c); print "@l @a\n" }},
    'the last statement, called in list context');
round_trips(q{my %h; for my $c (1,0) { my $x = $c ? ($h{k} = "s") : "n"; print "$x\n" }},
    'a hash element in a loop');
round_trips(q{my %h; for my $c (1,0) { my @r = ($c ? ($h{k} = "s") : "n"); print "@r\n" }},
    'list context');
round_trips(q{my @a = (0); for my $c (1,0) { print $c ? ($a[0] = 7) : 8, " @a\n" }},
    'a print argument');
refuses(q{my @a = (0); for my $c (1,0) { for my $d (1,0) { my $x = $c ? ($d ? ($a[0] = 1) : 2) : 3; print "$x @a;" } } print "\n";},
    $not_const, 'a nested ternary: the outer arm yields the inner merge');
round_trips(q{my @a = (0,0); for my $c (1,0) { my $x = $c ? ($a[0] = $a[1] = 5) : 8; print "$x @a\n" }},
    'a chained store');
round_trips(q{my %h; my $k = 0; for my $c (1,0) { my $x = $c ? ($h{$k++} = 5) : 8; print "$x $k ", join(",", map {"$_=$h{$_}"} sort keys %h), "\n" }},
    'a key with an effect');
round_trips(q{my $r = [0]; for my $c (1,0) { my $x = $c ? ($r->[0] = 7) : 8; print "$x @$r\n" }},
    'an arrayref element');
round_trips(q{our @A = (0); for my $c (1,0) { my $x = $c ? ($A[0] = 7) : 8; print "$x @A\n" }},
    'a package array element');
round_trips(q{my @a = (0); for my $c (1,0) { my $x = $c ? ($a[0] = 7) : ($a[0] = 8); $a[0]++; print "$x @a\n" }},
    'the value is a copy, not the element');
round_trips(q{my @a; my $k="ab"; for my $c (1,0) { my $x = $c ? ($a[0] = 1) : chop $k; print "$x $k @a\n" }},
    'a chop in the other arm');

# SAME at base, and must stay so.
round_trips(q{my @a=(0); my $n=0; sub f { $_[0] ? ($a[0]=7) : ($n=8) } print f(1), f(0), " $n @a\n"},
    'an element store beside a scalar store, last statement');
round_trips(q{my @a=(0); sub f { $_[0] ? ($a[0]=7) : ($a[1]=8) } my $s = f(1); my @l = f(0); print "$s @l @a\n"},
    'two element stores, last statement, scalar and list callers');
round_trips(q{my @a = (5); sub f { $_[0] ? ($a[0] = 7) : ($a[0] = $a[0] + 1) } print f(1), f(0), " @a\n"},
    'a stored expression as the last statement pushes nothing, as before');
round_trips(q{my %h; sub f { $_[0] ? ($h{$_[1]} = $_[2]) : ($h{z} = 0) } print f(1, "a", 4), f(0), " ", join(",", map {"$_=$h{$_}"} sort keys %h), "\n"},
    'a stored argument as the last statement');
round_trips(q{my @a=(0); sub f { $_[0] ? ($a[0]=7) : die "x\n" } print f(1), " @a\n";},
    'an element store beside a die, last statement');
round_trips(q{my @a=(0); for my $c (1,0) { my $x = $c ? push(@a,3) : 0; print "$x @a\n" }},
    'a push in an arm');
round_trips(q{my @a = (0); for my $c (1,0) { $c ? ($a[0] = 7) : ($a[0] = 8); print "@a\n" }},
    'the void form');

refuses(q{my @a=(1,2); for my $c (1,0) { my $x = $c ? $a[0]++ : 5; print "$x @a\n" }},
    $not_const, 'a postincrement');
refuses(q{my @a = (0, 3); for my $c (1,0) { my $x = $c ? ($a[0] += 2) : 8; print "$x @a\n" }},
    $not_const, 'an op-assign');
refuses(q{my @a=(5); for my $c (1,0) { my $x = $c ? ($a[0] = $a[0] + 1) : ($a[0] = $a[0] * 10); print "$x @a\n" }},
    $not_const, 'a stored value reading the element');
refuses(q{my @a=(1); my $r=\$a[0]; for my $c (1,0) { my $x = $c ? ($a[0] = $$r + 1) : 8; print "$x @a\n" }},
    $not_const, 'a stored value reading the element through a reference');
refuses(q{my @a=(1,2); for my $c (1,0) { for my $e (@a) { my $x = $c ? ($a[0] = $e + 1) : 8; print "$x @a;" } print "\n" }},
    $not_const, 'a stored value reading a foreach alias of the element');
refuses(q{my %h; my $k="ab"; for my $c (1,0) { my $x = $c ? ($h{chop $k} = $k) : 8; print "$x $k ", join(",", map {"$_=$h{$_}"} sort keys %h), "\n" }},
    $key_mem, 'a chop in the key');
refuses(q{my %h; my $k="ab\n"; for my $c (1,0) { my $x = $c ? ($h{chomp $k} = $k) : 8; print "[$x] [$k] ", join(",", map {"$_=$h{$_}"} sort keys %h), "\n" }},
    $key_mem, 'a chomp in the key');
refuses(q{my %h; my $k="ab"; for my $c (1,0) { my $x = $c ? ($h{undef $k} = $k) : 8; print defined $x ? $x : "u", " ", join(",", map {"$_=".($h{$_}//"u")} sort keys %h), "\n" }},
    $not_const, 'an undef in the key');
refuses(q{my @a; my $k="ab"; for my $c (1,0) { my $x = $c ? ($a[chop $k] = $k) : 8; print "$x $k\n" }},
    $key_mem, 'a chop in the index');
refuses(q{my %h; my $k="ab"; for my $c (1,0) { my $x = $c ? ($h{$k =~ tr/a/z/} = $k) : 8; print "$x $k ", join(",", map {"$_=$h{$_}"} sort keys %h), "\n" }},
    $not_const, 'a tr/// in the key');
refuses(q{sub inc { $_[0]++ } my @a=(0); for my $c (1,0) { my $x = $c ? inc($a[0]) : 5; print "$x @a\n" }},
    $not_const, 'a writing call of a lexical array element');

# The merged value re-reads the element after the store, through the same
# key. A key that reads memory -- an element, a size, keys -- reads it after
# the store too, and names another element; a key with an effect (chop,
# above) runs it again.
refuses(q{my @a = (0,5); for my $c (1,0) { my $x = $c ? ($a[$a[0]] = 1) : 8; print "$x @a\n" }},
    $key_mem, 'an index that reads the array');
refuses(q{my $r = [0,5]; for my $c (1,0) { my $x = $c ? ($r->[$r->[0]] = 1) : 8; print "$x @$r\n" }},
    $key_mem, 'an arrayref index that reads the array');
refuses(q{my @a = (0,5); my $c = shift // 1; my $x = $c ? ($a[$a[0]] = 1) : 8; print "$x @a\n"},
    $key_mem, 'an index that reads the array, outside a loop');
refuses(q{my %h = (k=>'k', x=>0); for my $c (1,0) { my $x = $c ? ($h{$h{k}} = 'z') : 8; print "$x $h{k}\n" }},
    $key_mem, 'a key that reads the hash');
refuses(q{my @a = (0,5); for my $c (1,0) { my $x = $c ? ($a[scalar(@a)] = 1) : 8; print "$x @a\n" }},
    $key_mem, 'an index that reads the size');
refuses(q{my %h = (a=>1); for my $c (1,0) { my $x = $c ? ($h{scalar(keys %h)} = 1) : 8; print "$x\n" }},
    $key_mem, 'a key that counts the keys');
refuses(q{my @a = (0,5); my @b = (1); for my $c (1,0) { my $x = $c ? ($a[$b[0]] = 1) : 8; print "$x @a\n" }},
    $key_mem, 'an index that reads another array');
# WANT 0 pushes nothing, as for a stored value that is not a constant: an
# if/else ending a sub (chalk's StructPromotion::_check_subscript_access,
# keyed on `$i->value()`) still yields its value and translates, as at base.
round_trips(q{my %h = (k=>'a'); sub f { if ($_[0]) { $h{$h{k}} = 7 } else { $h{z} = 8 } } print f(1), f(0), "\n";},
    'an if/else ending a sub, a key that reads the hash');
round_trips(q{package O { sub new { bless {v=>$_[1]}, $_[0] } sub value { $_[0]{v} } } my %s; sub f { my $i = shift; if ($i) { $s{k}{$i->value()} = 1 } else { $s{n} = 1 } } f(O->new("x")); f(0); print join(",", sort keys %s), " ", join(",", keys %{$s{k}}), "\n";},
    'an if/else ending a sub, a method call in the key');
round_trips(q{my @a = (0,5); my $i = 1; for my $c (1,0) { my $x = $c ? ($a[$i] = 1) : 8; print "$x @a\n" }},
    'a lexical scalar index');
round_trips(q{my @a = (0,0); my $i = 0; for my $c (1,0) { my $x = $c ? ($a[$i+1] = 1) : 8; print "$x @a\n" }},
    'an arithmetic index over a lexical scalar');

# `local` is restored at scope exit, which the store does not model.
refuses(q{my @a=(0); for my $c (1,0) { my $x = $c ? (local $a[0] = 7) : 8; print "$x $a[0]\n" }},
    qr/GAP: a consumed ternary arm localizes an element; its restore is not yet lowered/,
    'a local element');

# An lvalue ternary yields the element itself; a merged value is a copy.
my $lvalue = qr/GAP: a ternary whose arm stores an element is an lvalue/;
refuses(q{sub set { $_[0] = "w" } my @a=(0); my $z=8; for my $c (1,0) { set($c ? ($a[0]=7) : $z); print "@a $z\n" }},
    $lvalue, 'a call argument');
refuses(q{my @a=(0); my $z=8; for my $c (1,0) { my $r = \($c ? ($a[0]=7) : $z); $$r = 9; print "@a $z\n" }},
    $lvalue, 'a reference to the ternary');
refuses(q{sub set { $_[0] = "w" } my @a=(1,2); for my $c (1,0) { set($c ? $a[0] : $a[1]) } print "@a\n"},
    $lvalue, 'a ternary of lexical array elements passed to a writing call');

# Refused as before.
refuses(q{my @a=(0); for my $c (1,0) { my $x = eval { $c ? ($a[0]=7) : die "no\n" }; print defined $x ? $x : "u", " $a[0]\n" }},
    qr/GAP: value-context ternary with a branch-guarded element store not yet lowered/,
    'a die arm inside eval');
refuses(q{my @a = (0); for my $c (1,0) { my @r = ($c ? (($a[0]=1), 2) : 3); print "@r @a\n" }},
    qr/GAP: a ternary with a multi-element list arm not yet lowered/,
    'a multi-element list arm');

# DIFF at base too, by causes outside this ternary.
todo 'DIFF at base: a short-circuit drops its lhs value beside an element store' => sub {
    output_matches(q{my %h; for my $c (1,0) { my $x = $c && ($h{k} = 9); print "$x\n" }}, '&& with an element store');
};
todo 'DIFF at base: a void refgen does not vivify the element' => sub {
    output_matches(q{my %h; for my $c (1,0) { $c ? \$h{a} : 0; print exists $h{a} ? "e" : "n", "\n" }}, 'a void refgen arm');
};
todo 'DIFF at base: map does not vivify an aliased element' => sub {
    output_matches(q{my %h; my @r = map { $_ } $h{a}; print exists $h{a} ? "e" : "n", "\n"}, 'map over an element');
};
todo 'DIFF at base: a callee write into a lexical array element is lost' => sub {
    output_matches(q{sub set { $_[0] = "w" } my @a=(0,0); for my $c (1,0) { $c && set($a[$c]); print "@a\n" }}, 'set($a[$c]) under &&');
};
todo 'DIFF at base: a returned stored expression pushes nothing (renders return ())' => sub {
    output_matches(q{my @a = (5); sub f { return $_[0] ? ($a[0] = $_[1]) : 8 } print f(1, 3), f(0), " @a\n"}, 'return of a stored argument');
};
todo 'DIFF at base: a ternary ending a sub, whose key reads memory, pushes nothing' => sub {
    output_matches(q{my %h = (k=>'a'); sub f { $_[0] ? ($h{$h{k}} = 7) : 8 } my @r = (f(1), f(0)); print "@r\n"}, 'a WANT 0 ternary, a key that reads the hash');
};
todo 'DIFF at base: a glob alias of an element is not seen' => sub {
    output_matches(q{our $G; my @a=(1); *G = \$a[0]; $a[0] = $G + 1; print "@a\n"}, 'a glob alias');
};

done_testing;
