# ABOUTME: A store through a scalar reference under a guard inside an if arm is
# ABOUTME: guarded: the arm builds its If, so the store runs only when the guard holds.

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


round_trips(<<'SRC', 'a guarded decrement through a reference in an elsif arm');
sub f { my ($k, $r) = @_; if ($k eq "o") { $$r++ } elsif ($k eq "c") { $$r-- if $$r > 0; print "c$$r" } return $$r }
my $i = 0; print f("o", \$i), f("c", \$i), f("c", \$i), "\n";
SRC

round_trips(<<'SRC', 'the shape of chalk C::_emit_c_schedule_item');
sub f { my ($kind, $lines, $ind) = @_;
  if ($kind eq "stmt") { push @$lines, ("  " x $$ind) . "s" }
  elsif ($kind eq "open") { push @$lines, ("  " x $$ind) . "{"; $$ind++ }
  elsif ($kind eq "close") { $$ind-- if $$ind > 0; push @$lines, ("  " x $$ind) . "}" }
  else { die "unknown $kind" }
}
my @l; my $i = 0; f($_, \@l, \$i) for qw(close open stmt open stmt close close close); print join("|", @l), " $i\n";
SRC

done_testing;
