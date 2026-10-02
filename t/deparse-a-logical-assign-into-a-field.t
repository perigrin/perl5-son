# ABOUTME: `//=`, `||=` and `&&=` into a class field store into the field, on the arm that
# ABOUTME: assigns -- with a right side that has effects, which runs only on that arm.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

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


# THE VALUE WAS REBOUND AS A PAD SLOT, and a field is not one: perl 3,
# emitted U -- the store was dropped with no word. And with a call on the
# right the method refused, which is chalk's Node/BinOp.pm ADJUST:
# `$left //= $self->inputs()->[0]`.
my $class = <<'CLASS';
use v5.42; use experimental 'class';
class P {
  field $s :reader :param = undef;
  field $calls :reader = 0;
  method g($y) { $calls++; return $y * 10 }
CLASS

round_trips($class . <<'SRC', '`//=` into a field');
  method f($x) { $s //= $x; return } }
my $o = P->new; $o->f(3); $o->f(4); print $o->s, "\n";
SRC

round_trips($class . <<'SRC', '`||=` into a field');
  method f($x) { $s ||= $x; return } }
my $o = P->new(s => 0); $o->f(3); $o->f(4); print $o->s, "\n";
SRC

round_trips($class . <<'SRC', '`&&=` into a field');
  method f($x) { $s &&= $x; return } }
my $o = P->new(s => 5); $o->f(3); $o->f(4); print $o->s, "\n";
my $z = P->new(s => 0); $z->f(3); print $z->s, "\n";
SRC

round_trips($class . <<'SRC', '`//=` into a field from a call, run only when undefined');
  method f($x) { $s //= $self->g($x); return } }
my $o = P->new; $o->f(3); $o->f(4); print $o->s, " ", $o->calls, "\n";
SRC

round_trips($class . <<'SRC', '`||=` into a field from a call, run only when false');
  method f($x) { $s ||= $self->g($x); return } }
my $o = P->new(s => 0); $o->f(3); $o->f(4); print $o->s, " ", $o->calls, "\n";
SRC

round_trips($class . <<'SRC', 'the value of `//=` into a field');
  method f($x) { my $r = ($s //= $x); return "$r/$s" } }
my $o = P->new; print $o->f(3), " ", $o->f(4), "\n";
SRC

round_trips(<<'SRC', '`//=` into a field from a call in an ADJUST');
use v5.42; use experimental 'class';
class P {
  field $in :param;
  field $left :param :reader = undef;
  ADJUST { $left //= $self->first() }
  method first { return $in->[0] } }
print P->new(in => [7, 8])->left, " ", P->new(in => [7, 8], left => 1)->left, "\n";
SRC

done_testing;
