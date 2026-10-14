# ABOUTME: A return guarded inside an elsif arm keeps the elsif test: the arm leaves
# ABOUTME: from its own edge, so the guard is not dropped and the join has one input per path.

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


round_trips(<<'SRC', 'an elsif whose body is a guarded return, straight-line');
sub bal { my ($n, $k) = @_; if ($k eq "o") { print "o" } elsif ($k eq "e") { return 0 unless $n } return 1 }
print bal(1, "o"), bal(0, "e"), bal(1, "e"), bal(0, "x"), "\n";
SRC

round_trips(<<'SRC', 'an elsif whose body is a guarded return, in a loop');
sub bal { my $n = 0; for my $k (@_) { if ($k eq "o") { $n++ } elsif ($k eq "e") { return 0 unless $n } } return 1 }
print bal(qw(o e)), bal(qw(e)), bal(qw(x e)), "\n";
SRC

round_trips(<<'SRC', 'a stack check: the shape of chalk Schedule::is_balanced');
sub bal { my @stack;
  for my $k (@_) {
    if ($k eq "o") { push @stack, $k }
    elsif ($k eq "c") { return 0 unless @stack; my $top = pop @stack; return 0 unless defined $top && $top eq "o" }
    elsif ($k eq "e") { return 0 unless @stack }
  }
  return scalar(@stack) == 0;
}
print bal(qw(o c)), bal(qw(c)), bal(qw(o)), bal(qw(e)), bal(qw(o e c)), "\n";
SRC

done_testing;
