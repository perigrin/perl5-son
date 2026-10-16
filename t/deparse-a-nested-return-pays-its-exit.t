# ABOUTME: A return two guards deep in an arm whose sibling falls out to the exit pays
# ABOUTME: its own value into the exit variable before it returns.

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


# The emission must also be QUIET: a second `my @e` in one scope is a "masks
# earlier declaration" warning, and the masked variable is the defect.
sub emits_quietly ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}


round_trips(<<'SRC', 'the shape of chalk Precedence::_scan_multiply');
sub L::look { $_[1] eq "+" ? { level => 3, assoc => "left" } : undef }
sub f { my ($s, $e, $r, $m) = @_;
  if ($r eq "B" || $r eq "A") {
    my $info = $s->look($m);
    if (defined $info) {
      my $lvl = $info->{level};
      if (defined($e->{level}) && $e->{level} > $lvl) { return "z1" }
      if (defined($e->{level}) && $e->{level} == $lvl && $info->{assoc} eq "nonassoc") { return "z2" }
      return "op$lvl";
    }
    if ($r eq "A") {
      if (defined($e->{level})) {
        if ($e->{level} > 101) { return "z3" }
      }
      return "as";
    }
  }
  if ($r eq "S" && $m =~ /^[\[\{]$/ && defined($e->{level}) && $e->{level} >= 0) { return "z4" }
  return "one";
}
my $o = bless {}, "L";
print join(",", f($o, {level => 1}, "B", "+"), f($o, {level => 5}, "B", "+"), f($o, {}, "A", "="), f($o, {level => 200}, "A", "="), f($o, {level => 0}, "S", "["), f($o, {}, "B", "x")), "\n";
SRC

round_trips(<<'SRC', 'a guarded return inside a guard, beside a fall-through return');
sub f { my ($r, $l) = @_; if ($r eq "A") { if (defined $l) { if ($l > 101) { return "big" } } return "as" } return "one" }
print f("A", 200), f("A", 5), f("A", undef), f("B", 200), "\n";
SRC

done_testing;
