# ABOUTME: An element read of an array rebound under a condition -- a merge spelled as
# ABOUTME: a ternary -- is a list slice of that ternary; a store into one still refuses.

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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    if (!$data || $err =~ /skipped/) {
        fail "$name: translates"; diag $err; return;
    }
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

# `@controls = $controls[0]->@* if ...` MERGES TWO BINDINGS OF THE ARRAY, and
# a read of an element of the merge -- the grep inside chalk's
# TypedInvariant::check_nodes -- found a ternary with no sigil to switch to a
# `$`, and refused. A read of it is a list slice: `(C ? A->@* : B->@*)[$i]`.
round_trips(<<'SRC', 'an element of a conditionally rebound array, read by a grep');
use v5.42; use Scalar::Util qw(blessed);
package N { sub new { my ($c, %a) = @_; bless {%a}, $c } sub region { $_[0]{region} } sub inputs { $_[0]{inputs} } sub operation { $_[0]{op} } sub predecessors { undef } sub id { $_[0]{id} } }
sub arm { my ($n) = @_; return ref $n }
sub check { my ($nodes) = @_; my @v;
  for my $node ($nodes->@*) {
    my $region = $node->region;
    if (defined $region && blessed($region) && defined $region->inputs) {
      my @controls = $region->inputs->@*;
      @controls = $controls[0]->@* if @controls == 1 && ref $controls[0] eq 'ARRAY';
      my $values = $node->inputs // [];
      if (@controls && scalar($values->@*) != scalar(@controls)) { push @v, "n" . scalar(@controls) }
      if (@controls && !defined $node->predecessors && (grep { arm($_) } @controls) == @controls) { push @v, "p" . $region->id }
    }
  }
  return "@v" }
my $r1 = N->new(id => 1, inputs => [N->new, N->new]); my $r2 = N->new(id => 2, inputs => [[N->new, 1]]);
print check([N->new(region => $r1, inputs => [1, 2]), N->new(region => $r2, inputs => [1])]), "\n";
SRC

done_testing;
