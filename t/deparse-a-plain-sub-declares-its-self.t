# ABOUTME: `$self` in a plain sub is its own lexical, declared like any other;
# ABOUTME: only a class method's `$self` is perl's to provide.

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

# A SPLIT LIST ASSIGN -- its array declared ahead, a loop after -- left
# `($self, $to, @r) = (@_)` with no `my $self`: the undeclared-name pass skips
# `$self` for a class method, and a plain sub's is not one.
round_trips(<<'SRC', 'a plain method sub whose list assign takes an array');
package C; sub new { bless {}, shift } sub g { "g$_[1]" }
sub f {
    my ($self, $to, @r) = @_;
    my $val = '';
    for my $i (0 .. $#r) {
        my $repr = $r[$i];
        $val = $self->g($repr) if $repr ne $to;
    }
    return $val;
}
package main; print C->new->f('Str', qw(Int Num Str)), "\n";
SRC

# A STORE'S TARGET IS NOT A READ to bind at the top of the pass: bound, it was
# read before the store and its statement spelled bare -- "Useless use of
# private variable in void context" on the emitted program's stderr.
{
    my $src = <<'SRC';
package C; sub new { bless {}, shift } sub g { "g$_[1]" }
sub f { my ($self, $to, @r) = @_; my $val = '';
  for my $i (0 .. $#r) { my $repr = $r[$i]; $val = $self->g($repr) if $repr ne $to }
  return $val }
package main; print C->new->f('Str', qw(Int Num Str)), "\n";
SRC
    my $out = SoN::Deparse->new->render(graph_of($src)) // '';
    my $f = "$dir/w.pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    is scalar(qx($^X $f 2>&1)), "gNum\n",
        'a demoted store target is not read at the top of the pass';
}

done_testing;
