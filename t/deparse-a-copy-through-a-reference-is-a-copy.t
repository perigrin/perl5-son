# ABOUTME: `my %p = %$h` is a copy: a store through $h after it is not seen by %p,
# ABOUTME: whether %p is read straight after, or by element in a loop that stores.

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

# A COPY BOUND AS THE DEREFERENCE read the store made through it: `my %p =
# %$h; $h->{a} = 2; $p{a}` printed 2 for perl's 1 (chalk's
# IR::Schedule::Elaborate::_elaborate_if, `my %pre = %$val_map`).
round_trips(q{sub f { my ($h) = @_; my %p = %$h; $h->{a} = 2; return "$p{a} $h->{a}" } print f({a=>1}), "\n";},
    'a hash copied through a reference, then stored through it');
round_trips(q{sub f { my ($h) = @_; my @p = @$h; $h->[0] = 2; return "$p[0] $h->[0]" } print f([1]), "\n";},
    'an array copied through a reference, then stored through it');
round_trips(q{sub f { my ($h) = @_; my %p = %$h; for my $k (sort keys %p) { my $v = $p{$k}; $h->{$k} = $v + 10; print "$v $p{$k};" } return "" } print f({a=>1, b=>2}), "\n";},
    'a copy read in a loop that stores through the source');

# AN ELEMENT OF THE COPY NAMES THE COPY: `$stale3{a}` is `%stale3`, and the
# undeclared-name scan declared a stray `my $stale3` beside it.
{
    my $out = SoN::Deparse->new->render(graph_of(q{sub f { my ($h) = @_; my %p = %$h; $h->{a} = 2; return "$p{a}" } print f({a=>1}), "\n";})) // '';
    like $out, qr/my %stale\d+/, 'the copy is declared as a hash';
    unlike $out, qr/my \$stale\d+;/, 'and no scalar of its name';
}

done_testing;
