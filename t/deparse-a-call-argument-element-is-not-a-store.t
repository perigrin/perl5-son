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
my $elem_gap = qr/GAP: value-context ternary with a branch-guarded element store not yet lowered/;
refuses(q{sub set { $_[0] = "w" } my @a=(1,2); for my $c (1,0) { set($c ? $a[0] : $a[1]) } print "@a\n"},
    $elem_gap, 'a ternary of lexical array elements passed to a writing call');
refuses(q{sub inc { $_[0]++ } my @a=(0); for my $c (1,0) { my $x = $c ? inc($a[0]) : 5; print "$x @a\n" }},
    $elem_gap, 'a writing call of a lexical array element in an arm');

done_testing;
