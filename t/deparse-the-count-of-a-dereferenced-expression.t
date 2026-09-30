# ABOUTME: `scalar(@{ EXPR })` counts the aggregate EXPR refers to, whatever EXPR is --
# ABOUTME: a call, a shift, a variable -- rather than yielding the reference itself.

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

# THE COUNT HANDLER KEPT AN ALLOW-LIST of operand kinds (padsv, gvsv, helem,
# aelem), and anything else fell through with the rv2av dropped: the count
# was the reference. perl 2, emitted ARRAY(0x...).
round_trips(<<'SRC', 'the count of a call result');
sub r { my @x = (1, 2); return \@x } print scalar(@{ r() }), "\n";
SRC

round_trips(<<'SRC', 'the count of a call result, bound');
sub r { my @x = (1, 2, 3); return \@x } my $n = @{ r() }; print "$n\n";
SRC

round_trips(<<'SRC', 'the key count of a hash a call returns');
sub r { my %x = (a => 1, b => 2); return \%x } print scalar(%{ r() }), "\n";
SRC

round_trips(<<'SRC', 'the count of a shifted argument');
sub n { return scalar(@{ shift() }) } print n([4, 5, 6]), "\n";
SRC

round_trips(<<'SRC', 'the count through a variable, unchanged');
my $r = [1, 2]; print scalar(@$r), "\n";
SRC

done_testing;
