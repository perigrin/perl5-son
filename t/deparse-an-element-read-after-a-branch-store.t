# ABOUTME: An element read after a branch that stores the element sees the store: its
# ABOUTME: memory version is the join Phi, bound at the join; a merged arm reads the element.

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

# The renderer refuses: the producer translated it.
sub render_refuses ($src, $cause, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {});
    ok !defined $out, "$name: not rendered";
    like $d->gap // q{}, $cause, "$name: refused, naming its cause";
}

# The void form: the read after the join was bound in the entry prologue.
round_trips(q{my @a = (1); my $c = shift // 1; if ($c) { $a[0] = 7 } print "$a[0]\n";},
    'a void if, then a read');
round_trips(q{my @a = (1); my $c = shift // 1; my $y = $a[0]; if ($c) { $a[0] = 7 } print "$y $a[0]\n";},
    'a read before and after a void if');
round_trips(q{my @a = (1); my $c = shift // 1; my $y = $a[0]; if ($c) { $a[0] = 7 } else { $a[0] = 8 } print "$y $a[0]\n";},
    'if/else, both arms store');
round_trips(q{my @a = (1); my $c = shift // 1; $c ? ($a[0] = 7) : 8; print "$a[0]\n";},
    'a void ternary');

# A DIFFERENT CONSTANT HASH KEY is a different element: the loop pass, which
# now sees a store in an arm, does not refuse it.
round_trips(q{my %h = (a => 1); for my $c (1, 0) { my $y = $h{a}; if ($c) { $h{b} = 7 } my $z = $h{b} // "none"; print "$y $z\n" }},
    'in a loop, a different key');
round_trips(q{my %h = (a => 1); for my $c (1, 0) { my $y = $h{a}; my $x = $c ? ($h{b} = 7) : 8; print "$y $x $h{b}\n" }},
    'in a loop, a ternary, a different key');

# The consumed ternary: the same join, newly translated.
round_trips(q{my %h = (a=>1); my $c = shift // 1; my $y = $h{a}; my $x = $c ? ($h{a} = 7) : 8; print "$y $x $h{a}\n";},
    'a hash element read before and after');
round_trips(q{my @a = (1); my $c = shift // 1; my $y = $a[0]; my $x = $c ? ($a[0] = 7) : 8; print "$y $x $a[0]\n";},
    'an array element read before and after');
round_trips(q{our @a = (1); my $c = shift // 1; my $y = $a[0]; my $x = $c ? ($a[0] = 7) : 8; print "$y $x $a[0]\n";},
    'a package array');
round_trips(q{my $r = [1]; my $c = shift // 1; my $y = $r->[0]; my $x = $c ? ($r->[0] = 7) : 8; print "$y $x $r->[0]\n";},
    'through a reference');
round_trips(q{my %h = (a=>1); sub f { my $y = $h{a}; my $x = $_[0] ? ($h{a} = 7) : 8; print "$y $x $h{a}\n" } f(1);},
    'in a sub');
# In a loop the read before the store is spelled after it; that pass refuses.
render_refuses(q{my @a = (1); for my $c (1,0) { my $y = $a[0]; my $x = $c ? ($a[0] = 7) : 8; print "$y $x $a[0]\n" }},
    qr/GAP: an element read in a loop is spelled after a store to its aggregate/, 'in a loop');
render_refuses(q{my @a = (1); for my $c (1,0) { my $y = $a[0]; if ($c) { $a[0] = 7 } print "$y $a[0]\n" }},
    qr/GAP: an element read in a loop is spelled after a store to its aggregate/, 'in a loop, a void if');
round_trips(q{my @a = (1); my $c = shift // 1; my $y = $a[0] + 0; my $x = $c ? ($a[0] = 7) : 8; print "$y $x $a[0]\n";},
    'a prior read in an expression');
round_trips(q{my %h = (a=>1); my $c = shift // 1; my $y = $h{a}; my $x = $c ? ($h{b} = 7) : 8; print "$y $x $h{a} $h{b}\n";},
    'a different key stored');
round_trips(q{my %h = (a=>1); my $c = shift // 1; my $y = $h{a}; my $x = $c ? ($h{a} = 7) : 8; print "$y\n";},
    'only the earlier read printed');
round_trips(q{my %h = (a=>1); my $c = shift // 1; my $x = $h{a} ? ($h{a} = 7) : 8; print "$x $h{a}\n";},
    'the condition reads the element');
round_trips(q{my %h = (a=>1); my $c = shift // 1; my $x = $c ? ($h{a} = 7) : $h{a}; my $z = $h{a}; print "$x $z\n";},
    'the other arm reads the element');
round_trips(q{my %h = (a=>1); sub g { $_[0] = 5; 3 } my $c = shift // 1; my $y = $h{a}; my $x = $c ? g($h{a}) : 8; print "$y $x $h{a}\n";},
    'a call writes the element through @_');
round_trips(q{my %h = (a=>1); sub g { $_[0] = 5; 3 } my $c = shift // 1; my $y = $h{a}; if ($c) { g($h{a}) } print "$y $h{a}\n";},
    'a call writes the element through @_, void if');

round_trips(q{my %h = (a=>1); my $c = shift // 1; my $y = $h{a}; if ($c) { $h{a} = 7 } elsif ($y) { $h{a} = 9 } print "$y $h{a}\n";},
    'an elsif condition reads the element');
round_trips(q{my %h = (a=>1); my $c = shift // 1; my $y = $h{a}; if ($c) { $h{a} = 7 } my $z = $h{a}; $h{a} = 9; print "$y $z $h{a}\n";},
    'a read at the join, then another store');
round_trips(q{our @a = (1); sub f { my $y = $a[0]; my $x = $_[0] ? ($a[0] = 7) : 8; print "$y $x $a[0]\n" } f(1); f(0);},
    'a package array in a sub');
round_trips(q{my %h = (a=>1); sub f { my $y = $h{a}; $h{a} = 7; print "$y $h{a}\n" } f();},
    'a closed-over hash read at sub entry');

# A TIED ELEMENT: sassign yields the element, so the merged value is FETCH
# after STORE, not the constant stored.
my $tie_h = q{package T; sub TIEHASH { bless {}, shift } sub STORE { $_[0]{$_[1]} = $_[2] * 10 } sub FETCH { $_[0]{$_[1]} } package main; tie my %h, q{T}; };
round_trips($tie_h . q{for my $c (1,0) { my $x = $c ? ($h{a} = 7) : 8; print "$x $h{a}\n" }}, 'a tied hash');
round_trips($tie_h . q{sub f { $_[0] ? ($h{a} = 7) : ($h{b} = 8) } print f(1), f(0), "\n";}, 'a tied hash, both arms, WANT 0');
round_trips($tie_h . q{my $c = shift // 1; print $c ? ($h{a} = 7) : 8, "\n";}, 'a tied hash, a print argument');
round_trips(q{package T; sub TIEARRAY { bless [], shift } sub STORE { $_[0][$_[1]] = "$_[2]!" } sub FETCH { $_[0][$_[1]] } sub FETCHSIZE { scalar @{$_[0]} } package main; tie my @a, q{T}; for my $c (1,0) { my $x = $c ? ($a[0] = 7) : 8; print "$x\n" }},
    'a tied array');

done_testing;
