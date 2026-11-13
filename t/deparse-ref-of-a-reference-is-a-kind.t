# ABOUTME: `ref \EXPR` asks what kind of thing EXPR is (reftype_of_ref): no reference
# ABOUTME: is made, so one to a foreach alias cannot outlive its pass.

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
    is producer_stderr(), '', "$name: the producer says nothing";
    return fail "$name: translates" unless $data;
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    is run_perl($out), $want, $name or diag "--- emitted ---\n$out";
}

round_trips(q{my $x = 1; my @a = (1); print ref \$x, " ", ref \@a, " ", ref \\$x, "\n";}, 'of a scalar, an array, a reference');
round_trips(q{for my $e (1, [2]) { print ref \$e, " " } print "\n";}, 'of a lexical foreach alias');
round_trips(q{our @G = (1, \"s"); for (@G) { print ref \$_, " " } print "\n";}, 'of a package foreach alias');
round_trips(q{sub k { my ($p) = @_; $p .= '::'; return 'no' unless exists $::{$p}; for ($::{$p}) { return ref \$_ } } print k("main"), " ", k("Nope"), "\n";}, 'of a stash entry (Carp::_fetch_sub)');

done_testing;
