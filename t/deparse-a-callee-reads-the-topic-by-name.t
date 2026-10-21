# ABOUTME: A callee reads or writes the caller's foreach topic `$_` by name: the topic is
# ABOUTME: aliased to the element each pass with `\local $_`, as perl's foreach does.

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

# Either the emission matches perl, or the producer or deparser refuses
# naming $cause.
sub round_trips_or_refuses ($src, $cause, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {});
    return like producer_stderr() || $d->gap // '', $cause, "$name: refused, naming its cause"
        unless defined $out;
    is run_perl($out), run_perl($src), $name or diag "--- emitted ---\n$out";
}

# THE LOWERED LOOP NEVER SET `$_`: the body's own reads of the topic are
# the element by index, but a callee reads the global by name -- empty, for
# perl's `12`. Each pass now aliases it, `\local $_ = \$a[$i]`, restored at
# the end of the pass as perl restores the foreach variable.
round_trips(q{sub g { print $_ } sub f { my @a = (1, 2); g() for @a; print "\n" } f();},
    'a callee reading the topic');
round_trips(q{sub g { $_ = 100 } sub f { my @a = (1, 2); for (@a) { g() } print "@a\n" } f();},
    'a callee writing the topic');
round_trips(q{sub g { print $_ } sub f { my @a = (1, 2); $_ = "top"; g() for @a; print "|$_\n" } f();},
    'the topic is restored after the loop');
round_trips(q{sub g { print $_ } sub f { my @a = (1, 2); my @b = (7, 8); for (@a) { g() for @b; g() } print "\n" } f();},
    'a nested loop over the topic');
round_trips(q{sub g { print $_ // "u" } sub f { my @a; $a[1] = 2; g() for @a; print exists $a[0] ? "e" : "n", "\n" } f();},
    'a hole the topic passes over stays a hole');
round_trips(q{sub g { $_[0] = $_ * 10 } sub f { my @a = (1, 2); g($_) for @a; print "@a\n" } f();},
    'the topic passed and read by name');
# chalk's Analysis::_narrow_unknown_coercions: a method on each element of an
# array the sub filled by push.
round_trips(q{package N { sub new { bless { s => $_[1] }, $_[0] } sub set_stamp { $_[0]{s} = $_[1] } sub s { $_[0]{s} // "u" } }
sub f { my @stale; push @stale, N->new(1), N->new(2); $_->set_stamp(undef) for @stale; return join ",", map { $_->s } @stale }
print f(), "\n";},
    'a method on each element of a pushed array');

# A MAP OR GREP ALIASES THE TOPIC THE SAME WAY: `grep { is_x() } @a` with
# `sub is_x { /x/ }` matched an undef topic -- `|0 0 0` for perl's
# `ax xc|1 0 1`.
round_trips(q{sub is_x { /x/ } sub f { my @a = qw(ax b xc); my @g = grep { is_x() } @a; my @m = map { is_x() ? 1 : 0 } @a; print "@g|@m\n" } f();},
    'a callee reading the topic of a map and a grep');
round_trips(q{sub g { print $_ } sub f { my @a = (1, 2); my @b = (7, 8); for (@a) { my @r = map { g(); $_ } @b; g() } print "\n" } f();},
    'a map inside a foreach, each with its own topic');

# A RANGE'S TOPIC is a fresh value each pass: `45` for perl's `12345`.
round_trips(q{sub g { print $_ } sub f { g() for 1 .. 3; for (4, 5) { g() } print "\n" } f();},
    'a callee reading the topic of a range');
round_trips(q{sub g { $_ .= "x"; print $_ } sub f { my $n = 0; for (1 .. 2) { g(); $n += $_ } print "|$n\n" } f();},
    'a callee writing the topic of a range');

# A LIST REBOUND UNDER A CONDITION is a ternary, spelled as its list slice:
# no element to refer to, so the topic is a copy of it.
round_trips(q{sub is_x { /x/ } sub f { my @c = @_; @c = $c[0]->@* if @c == 1 && ref $c[0] eq 'ARRAY'; return join ",", grep { is_x() } @c } print f([qw(ax b xc)]), "|", f(qw(x y)), "\n";},
    'a callee reading the topic over a conditionally rebound list');

# OVER A DEREFERENCE A CALLEE MIGHT REACH, a body that reads the topic only
# before its first call reads what perl's alias holds then; the callee sees
# the alias itself (chalk's EmitHelpers::_collect_all_var_refs,
# `$walk->($_) for $input->@*`).
round_trips(q{sub f { my ($t) = @_; my @seen; my $walk; $walk = sub ($n) { return unless ref $n; push @seen, $n->{v}; $walk->($_) for $n->{kids}->@* }; $walk->($t); return "@seen" } print f({ v => 1, kids => [{ v => 2, kids => [] }, { v => 3, kids => [{ v => 4, kids => [] }] }] }), "\n";},
    'a recursive closure called on the topic over a dereference');
round_trips(q{sub g { $_ .= "!" } sub f { my ($r) = @_; g($_) for $r->@*; return "@$r" } print f([1, 2]), "\n";},
    'a callee writing the topic over a dereference');
# A READ AFTER THE CALL may see a list the callee reshaped: still refused.
my $REACH = qr/GAP: a foreach over an unproven list/;
round_trips_or_refuses(q{sub g { shift @{$_[0]} } sub f { my ($r) = @_; my $s = ""; for (@$r) { g($r); $s .= $_ } return "$s|@$r" } print f([1, 2, 3]), "\n";},
    $REACH, 'a topic read after a call that may reshape the dereferenced list');

# A LIST A BUILTIN MADE has no holes, and `exists((values %h)[$i])` does not
# compile: only a container is guarded (chalk's IR::Graph::nodes).
round_trips(q{sub g { $_ * 2 } sub f { my %h = (a => 1, b => 2); my $s = 0; for (values %h) { $s += g() } return $s } print f(), "\n";},
    'a callee reading the topic over the values of a hash');
round_trips(q{sub g { $_ } sub f { my @a = (3, 1, 2); my $s = ""; $s .= g() for sort @a; return $s } print f(), "\n";},
    'a callee reading the topic over a sorted list');

round_trips(q{package N { sub new { bless { i => $_[1] }, $_[0] } sub id { $_[0]{i} } } sub f { my %c = (a => N->new(1), b => N->new(2)); my %m; my @f = values %c; $m{ $_->id } = $_ for @f; return join ",", sort keys %m } print f(), "\n";},
    'a method on the topic over an array bound to a builtin list');

done_testing;
