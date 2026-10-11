# ABOUTME: An element passed to a call or sprintf is a deferred lvalue, not a store: a ternary
# ABOUTME: or short-circuit holding one round trips; a lexical array element keeps refusing.

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

sub refuses ($src, $cause, $name) {
    graph_of($src);
    like producer_stderr(), $cause, "$name: refused, naming its cause";
}

# The chalk shapes: a ternary over elements in a call's argument list, and
# a call or sprintf of an element in an arm.
round_trips(q{sub g { return join ",", @_ } sub f { my %o = @_; return g(r => (exists $o{a} ? $o{a} : 'dflt')) } print f(a => 1), " ", f(b => 2), "\n";},
    'a hash-element ternary in a call argument list');
round_trips(q{my $h = {b => 65}; for my $c (1,0) { my $x = $c ? chr($h->{b}) : sprintf("%d", $h->{b}); print "$x\n" }},
    'an element in a builtin and a sprintf argument');
round_trips(q{sub g { "<@_>" } sub f { my $r = $_[0]; $_[1] ? g($r->[0]) : 'none' } print f([5],1), f([5],0), "\n";},
    'a call of an element as the last statement');
round_trips(q{sub g { "<@_>" } sub f { my $r = $_[0]; return $_[1] ? g($r->[0]) : 'none' } print f([5],1), f([5],0), "\n";},
    'a call of an element under return');

# The callee writes through $_[0]; the call pins the write.
round_trips(q{sub inc { $_[0]++ } my %h; for my $c (1,0) { my $x = $c ? inc($h{k}) : 5; print $x, " ", exists $h{k} ? "e" : "n", "\n" }},
    'a callee vivifies the hash element it is passed');
round_trips(q{sub set { $_[0] = "w" } my %h=(a=>1,b=>2); for my $c (1,0) { set($c ? $h{a} : $h{b}) } print "$h{a} $h{b}\n"},
    'a ternary of hash elements passed to a writing call');
round_trips(q{sub set { $_[0] = "w" } my $r=[1,2]; for my $c (1,0) { set($c ? $r->[0] : $r->[1]) } print "@$r\n"},
    'a ternary of arrayref elements passed to a writing call');
round_trips(q{sub inc { $_[0]++ } my $r=[0]; for my $c (1,0) { my $x = $c ? inc($r->[0]) : 5; print "$x @$r\n" }},
    'a writing call of an arrayref element in an arm');
round_trips(q{our @A=(0); sub inc { $_[0]++ } for my $c (1,0) { my $x = $c ? inc($A[0]) : 5; print "$x @A\n" }},
    'a writing call of a package array element in an arm');

# Short-circuits share the predicate.
round_trips(q{my %h = (k => 0); for my $c (1,0) { my $x = $c && sprintf("%d", $h{k}); print "[$x]\n" }},
    'a sprintf of an element under &&');
round_trips(q{my %h = (k => 0); for my $c (1,0) { my $x = $c || sprintf("%d", $h{k}); print "[$x]\n" }},
    'a sprintf of an element under ||');
round_trips(q{sub g { "<@_>" } my %h = (k => 1); for my $c (1,0) { my $x = $c || g($h{k}); print "[$x]\n" }},
    'a call of an element under ||');
round_trips(q{sub inc { $_[0]++ } my %h; for my $c (1,0) { $c && inc($h{k}); print $h{k} // "u", "\n" }},
    'a void && calling a writer of an element');

# A LEXICAL ARRAY element's write through $_[0] is not modelled
# (`set($a[$i])` loses it), so it keeps refusing in a consumed arm.
refuses(q{sub set { $_[0] = "w" } my @a=(1,2); for my $c (1,0) { set($c ? $a[0] : $a[1]) } print "@a\n"},
    qr/GAP: a ternary whose arm stores an element is an lvalue/, 'a ternary of lexical array elements passed to a writing call');
refuses(q{sub inc { $_[0]++ } my @a=(0); for my $c (1,0) { my $x = $c ? inc($a[0]) : 5; print "$x @a\n" }},
    qr/GAP: a consumed ternary arm stores an element and yields a value that is not a constant/,
    'a writing call of a lexical array element in an arm');

# A CALL WRITES ITS ELEMENT ARGUMENT through $_[0]. A read of that element
# earlier in a loop iteration is spelled at its use, after the call, so the
# loop pass counts the call as a store to the aggregate it is passed from.
sub render_refuses ($src, $cause, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {});
    ok !defined $out, "$name: not rendered";
    like $d->gap // q{}, $cause, "$name: refused, naming its cause";
}
my $loop_gap = qr/GAP: an element read in a loop is spelled after a store to its aggregate/;
render_refuses(q{sub g { $_[0] = 5; 1 } my %h=(a=>1); for my $c (1,0) { my $y = $h{a}; g($c ? $h{a} : my $t); print "$y $h{a}\n" }},
    $loop_gap, 'a ternary element argument after a read, in a loop');
render_refuses(q{sub g { $_[0] = 5; 1 } my $r={a=>1}; for my $c (1,0) { my $y = $r->{a}; g($c ? $r->{a} : my $t); print "$y $r->{a}\n" }},
    $loop_gap, 'a hashref element');
render_refuses(q{sub g { $_[0] = 5; 1 } our %g=(a=>1); for my $c (1,0) { my $y = $g{a}; g($c ? $g{a} : my $t); print "$y $g{a}\n" }},
    $loop_gap, 'a package hash element');
render_refuses(q{sub g { $_[0] = 5; 1 } my %h=(a=>1); for my $c (1,0) { my $y = $h{a}; g($h{a}); print "$y $h{a}\n" }},
    $loop_gap, 'a plain element argument after a read, in a loop');
render_refuses(q{sub g { $_[0] = 5 } my %h=(a=>1); for my $c (1,0) { my $x = sprintf("%s", $c ? $h{a} : 8); g($h{a}); print "$x $h{a}\n" }},
    $loop_gap, 'a sprintf of a ternary element before a writing call, in a loop');
round_trips(q{sub g { $_[0] = 5; 1 } my %h=(a=>1,b=>2); for my $c (1,0) { my $y = $h{a}; g($c ? $h{b} : my $t); print "$y $h{a} $h{b}\n" }},
    'a different key passed');
round_trips(q{sub g { $_[0] = 5; 1 } my %h=(a=>1); for my $c (1,0) { g($h{a}); my $y = $h{a}; print "$y\n" }},
    'a read after the call');

# A sprintf ARGUMENT IS A READ, not an lvalue: built as an address it took no
# memory version, and was spelled after a later write to the element.
round_trips(q{sub g { $_[0] = 5 } my %h=(a=>1); my $c = 1; my $x = sprintf("%s", $c ? $h{a} : 8); g($h{a}); print "$x $h{a}\n"},
    'a sprintf of a ternary element before a writing call');
round_trips(q{sub g { $_[0] = 5 } my %h=(a=>1); my $x = sprintf("%s", $h{a}); g($h{a}); print "$x $h{a}\n"},
    'a sprintf of an element before a writing call');
round_trips(q{my %h=(a=>1); my $x = sprintf("%s", $h{a}); $h{a} = 5; print "$x $h{a}\n"},
    'a sprintf of an element before a store');
round_trips(q{my @a=(1); my $x = sprintf("%d", $a[0]); $a[0] = 5; print "$x @a\n"},
    'a sprintf of an array element before a store');
round_trips(q{my $r={a=>1}; my $c = shift // 1; my $x = sprintf("%s", $c ? $r->{a} : 8); $r->{a} = 5; print "$x $r->{a}\n"},
    'a sprintf of a ternary hashref element before a store');

done_testing;
