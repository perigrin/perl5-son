# ABOUTME: A list read through a reference is the aggregate's contents where it
# ABOUTME: is written, not where its value is next spelled.

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



# A LIST READ OF A DEREFERENCED AGGREGATE is the contents at that point: a
# later push, store or call does not reach back into a copy already taken.
for my $case (
    [q{use v5.36; sub f ($x = [3,1,2]) { my @s = sort { $a <=> $b } @$x; push @$x, 0; "@s|@$x" } print f(), " ", f([2,1]), "\n";},
        'a sorted copy before a push, under an allocating default'],
    [q{use v5.36; sub g { [] } sub f ($x = g()) { my @s = sort { $a <=> $b } @$x; push @$x, 0; "@s|@$x" } print f(), " ", f([2,1]), "\n";},
        'a sorted copy before a push, under a calling default'],
    [q{use v5.36; sub f ($x) { my @s = sort { $a <=> $b } @$x; push @$x, 0; "@s|@$x" } print f([2,1]), "\n";},
        'a sorted copy before a push'],
    [q{use v5.36; sub f ($x = [3,1,2]) { my @s = reverse @$x; push @$x, 0; "@s|@$x" } print f(), " ", f([2,1]), "\n";},
        'a reversed copy before a push'],
    [q{sub f { my $x = shift; my @s = @$x; push @$x, 0; "@s|@$x" } print f([2,1]), "\n";},
        'a copy before a push'],
    [q{sub f { my $x = shift; my $n = @$x; push @$x, 0; "$n|@$x" } print f([2,1]), "\n";},
        'a count before a push'],
    [q{sub f { my $x = shift; my @s = (9, @$x); push @$x, 0; "@s|@$x" } print f([2,1]), "\n";},
        'a list holding a copy before a push'],
    [q{sub f { my $x = shift; my @s = @$x; $x->[0] = 7; "@s|@$x" } print f([2,1]), "\n";},
        'a copy before an element store'],
    [q{my $x = [2,1]; my @s = @$x; push @$x, 0; print "@s|@$x\n";},
        'a copy before a push at the top level'],
    [q{sub f { my $x = shift; push @$x, scalar(@$x); "@$x" } print f([2,1]), "\n";},
        'a count inside the push it precedes'],
) {
    round_trips(@$case);
}

# A HASH'S KEYS READ THROUGH A REFERENCE go stale the same way: `keys %$h`
# was spelled after a later store and counted its key (`a,b` for `a`).
round_trips(q{sub f { my $h = {a=>1}; my $k = join ",", sort keys %$h; $h->{b} = 2; return $k } print f(), "\n";},
    'the keys of a referenced hash, read before a store');
round_trips(q{sub f { my ($self) = @_; my $r = ""; { local $self->{k} = 5; $r = join ",", sort keys %$self } return "$r / " . join(",", sort keys %$self) } print f({ a => 1 }), "\n";},
    'the keys read inside a block whose local is restored');

# A REFERENCE A LIST ASSIGNMENT BINDS -- `my ($x) = @_` -- is a pad variable
# the chain's Assign gives its value, neither a parameter nor made on the
# chain itself: the read was left live and spelled after the push (`123`
# for perl's `12`, a count of 3 for 2). `my $x = shift` was right.
round_trips(q{sub f { my ($x) = @_; my $s = join "", @$x; push @$x, 3; return "$s|@$x" } print f([1,2]), "\n";},
    'a list read through a reference a list assignment bound, before a push');
round_trips(q{sub f { my ($x) = @_; my $n = scalar(@$x); push @$x, 3; return "$n|@$x" } print f([1,2]), "\n";},
    'a count through a reference a list assignment bound, before a push');
round_trips(q{sub g { $_[0] = 9 } sub f { my ($x) = @_; my $s = join "", @$x; g($$x[0]); return "$s|@$x" } print f([1,2]), "\n";},
    'a list read through a reference a list assignment bound, before a callee writes an element');
# THROUGH AN ELEMENT OF ONE, too: `scalar @{ $self->{s} }` read before the
# push was spelled after it (chalk's LLVM::Context::_module_global_name named
# every global one index too high).
round_trips(q{sub f { my ($self, $t) = @_; my $g = scalar @{ $self->{s} }; my $n = "x$g"; push $self->{s}->@*, [$n, $t]; return ($n, $g) } my $o = { s => [] }; print join(",", f($o, "a"), f($o, "b")), "\n";},
    'a count through an element of a bound reference, before a push');

done_testing;
