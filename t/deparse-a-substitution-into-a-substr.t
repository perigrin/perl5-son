# ABOUTME: An s/// whose subject is substr($s, o, l) substitutes into that part
# ABOUTME: of $s: the part read, substituted, and written back (4-argument substr).

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

round_trips(q{my $p = "aXbXX"; substr($p, 0, -1) =~ s/X/Q/g; print "$p\n";},
    'a literal replacement, /g');
round_trips(q{my $p = "aXbXX"; substr($p, 1, 3) =~ s/X/Q/; print "$p\n";},
    'one substitution');
# Its count: the producer takes it; the deparser has no lvalue to name, and
# says so (T2 lowers it: chalk's own test).
{
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of(q{my $p = "aXbXX"; my $n = (substr($p, 0, 4) =~ s/X/Q/g); print "$n $p\n";}));
    is producer_stderr(), '', 'its count: the producer says nothing';
    like $d->gap // '', qr/GAP: a counted s\/\/\/ whose subject is a `Call`/, 'its count: the deparser refuses by name';
}
round_trips(q{my $p = "aXbXX"; substr($p, 0, -1) =~ s/X/lc("Q") . "!"/ge; print "$p\n";},
    'a code replacement, /ge');
round_trips(q{my $p = "abc"; substr($p, 0, 2) =~ s/Z/Q/g; print "$p\n";},
    'no match leaves it as it was');
# File::Temp's _replace_XX: Xs before the suffix, from a file lexical array.
round_trips(q{my @C = qw/Q/; sub r { my ($path, $ignore) = @_; my $end = "\\z"; if ($ignore) { substr($path, 0, - $ignore) =~ s/X(?=X*$end)/$C[ int( rand( @C ) ) ]/ge } else { $path =~ s/X(?=X*$end)/$C[ int( rand( @C ) ) ]/ge } return $path } print r("aXbXXX", 0), " ", r("fXXXX.tmp", 4), "\n";},
    'File::Temp\'s _replace_XX');

done_testing;
