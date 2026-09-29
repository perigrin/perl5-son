# ABOUTME: A `state` initialiser in the program's straight line runs exactly
# ABOUTME: once, as a `my` would; one that can run again refuses by name.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

# A TIME LIMIT, as for every loop test: a wrong lowering can spin.
sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; diag producer_stderr(); return;
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

# THE INITIALISER WAS DROPPED. `state $n = 1` compiles to a `once` op whose
# ->other is the store; nothing handled `once`, so the walk stepped past it and
# every read of $n was of nothing. Corpus 087 and 005.
round_trips(<<'SRC', 'state at file scope and in a bare block');
use feature "state";
state $n = 1;
{
  state $n = 2;
  print "$n\n";
}
print "$n\n";
SRC

round_trips(<<'SRC', 'state beside our and my, shadowed in a block');
use feature "state";
our $g = 1;
my $x = 2;
state $s = 3;
{
  local $g = $g + 10;
  my $x = $x * 2;
  state $s = $s + 100;
  print "$g $x $s\n";
}
print "$g $x $s\n";
SRC

# A `state` THAT CAN RUN AGAIN persists between runs -- that is not a `my`.
{
    my $data = graph_of(<<'SRC');
use feature "state";
sub counter { state $c = 0; $c++; return $c }
print counter(), counter(), "\n";
SRC
    ok !($data && $data->{methods}{'main::counter'}),
        'a state in a sub does not translate';
    like producer_stderr(), qr/`state` initialiser that can run more than once/,
        '... and says why';
}

done_testing;
