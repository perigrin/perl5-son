# ABOUTME: `exists` and `delete` on an element through a reference index a hash or an
# ABOUTME: array as the op says; the reference's stamp cannot tell which.

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


round_trips(<<'SRC', 'exists on a hash element through a parameter');
sub f { my ($h) = @_; return exists $h->{a} ? "y" : "n" }
print f({a => undef}), f({}), "\n";
SRC

round_trips(<<'SRC', 'exists on an array element through a parameter');
sub f { my ($r) = @_; return exists $r->[1] ? "y" : "n" }
print f([1, 2]), f([1]), "\n";
SRC

round_trips(<<'SRC', 'delete of a hash element through a parameter');
sub f { my ($h) = @_; delete $h->{a}; return 1 }
my %h = (a => 1, b => 2); f(\%h); print join(",", sort keys %h), "\n";
SRC

round_trips(<<'SRC', 'delete of an array element through a parameter');
sub f { my ($r) = @_; return delete $r->[2] }
my @a = (1, 2, 3); print f(\@a), scalar(@a), "\n";
SRC

# Reduced from chalk's Desugar::_create_helpers.
round_trips(<<'SRC', 'a store guarded by !exists in an if arm');
sub f { my ($h, $q) = @_; if ($q eq "+") { if (!exists $h->{a}) { $h->{a} = 1 } $h->{b} = 2 } return 1 }
my %h; f(\%h, "+"); print join(",", sort keys %h), "\n";
SRC

done_testing;
