# ABOUTME: `local` on a hash or array element: stored now, restored at the
# ABOUTME: scope's exit -- emitted as `local` so perl restores it, die and all.

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

# chalk's LLVM::Context guards recursion with `local $self->{_inlining} =
# {...}` and isolates a cache with `local $self->{cache} = {}` inside an if.
# A sub's own top-level local is restored after its value is made, where
# nothing in the graph can see it; a nested block's is restored at the
# block's end, and a later read in the sub sees the old value again.
my $H = q{sub h { my $s = shift; join ",", map { "$_=" . (ref $s->{$_} ? "{" . join("", sort keys %{$s->{$_}}) . "}" : $s->{$_} // "u") } sort keys %$s }
};
round_trips($H . q{sub f { my ($self, $n) = @_; local $self->{c} = { ($self->{c} // {})->%*, $n => 1 }; return h($self) }
my $s = { a => 1 }; print f($s, "x"), " | ", h($s), "\n";},
    'a sub-level local a callee sees, gone after');
round_trips($H . q{sub f { my ($self, $n) = @_; my $r = ""; if ($n) { local $self->{c} = $n; $r = h($self) } return "$r / " . h($self) }
my $s = { a => 1, c => 0 }; print f($s, "x"), " | ", f($s, ""), " | ", h($s), "\n";},
    'a local in an if block, read after the block');
round_trips($H . q{sub f { my ($self) = @_; my $r = ""; { local $self->{k} = 5; $r = h($self) } return "$r / " . h($self) . " / " . (exists $self->{k} ? "e" : "ne") }
my $s = { a => 1 }; print f($s), "\n";},
    'a local on a key that did not exist is deleted again');
round_trips($H . q{sub g { my $s = shift; die "boom\n" if $s->{c} } sub f { my ($self) = @_; local $self->{c} = 1; g($self); return "no" }
my $s = { a => 1 }; my $r = eval { f($s) } // "caught"; print "$r ", h($s), "\n";},
    'a callee dies past the local, and the caller catches');
round_trips($H . q{sub f { my ($self) = @_; my $r = ""; for my $i (1 .. 2) { local $self->{c} = $i; $r .= h($self) . ";" } return $r . h($self) }
my $s = { a => 1 }; print f($s), "\n";},
    'a local in a loop body');
round_trips(q{my %h = (a => 1); sub g { "a=$h{a}" } sub f { local $h{a} = 2; return g() } print f(), " ", g(), "\n";},
    'a local on a shared hash element');

# A PACKAGE VARIABLE'S local IN AN if ARM was never restored: the arm walk
# had no scope exit, so `g=2 g=2` printed for perl's `g=2 g=1`.
round_trips(q{our $g = 1; sub g { "g=$g" } sub f { my $r = ""; if ($_[0]) { local $g = 2; $r = g() } return "$r " . g() } print f(1), " | ", f(0), " | $g\n";},
    'a package local in an if arm is restored at its end');
round_trips(q{our $g = 1; sub g { "g=$g" } sub f { my $r = ""; if ($_[0]) { local $g = 2; $r = g() } else { local $g = 3; $r = g() } return "$r " . g() } print f(1), " | ", f(0), " | $g\n";},
    'a package local in each arm');

# A FOLDED `if (1)` IS A PLAIN BLOCK, which the main walk entered and left
# without a restore: a package local outlived it (perl 1, emitted 5).
round_trips(q{our $g = 1; sub g { print "g=$g\n" } if (1) { local $g = 5; g() } g();},
    'a package local in a folded block at program scope');
round_trips(q{our $g = 1; sub g { print "g=$g\n" } sub f { if (1) { local $g = 5; g() } g() } f();},
    'a package local in a folded block in a sub');

# A LOOP AFTER THE LOCAL IS NO SCOPE OF IT: `$x->{b}{$_} = 1 for @args`
# ended in leaveloop, which restored the sub's own `local` before the call
# that reads it (chalk's LLVM::Context::_lower_call_direct).
round_trips(<<'SRC', 'a local before a for modifier, read by a call after it');
package C; sub new { bless { cache => {}, bind => undef }, shift }
sub inner { my ($self) = @_; join ",", sort keys(($self->{bind} // {})->%*) }
sub f { my ($self, @args) = @_;
  unless (@args) { my $r = $self->inner; $self->{cache}{n} = $r; return $r }
  local $self->{bind} = { ($self->{bind} // {})->%* };
  $self->{bind}{$_} = 1 for @args;
  my $r = $self->inner;
  $self->{cache}{n} = $r;
  return $r }
package main; my $o = C->new; print $o->f(), "|", $o->f(qw(a b)), "|", $o->inner, "\n";
SRC

done_testing;
