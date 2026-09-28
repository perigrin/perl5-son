# ABOUTME: `&name;` passes the CALLER's @_ through; `&name()`, `name()` and
# ABOUTME: `name` pass nothing. The graph records which, and the emission keeps it.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; return;
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

# FOUR SPELLINGS, TWO MEANINGS. Measured, the entersub flags:
#
#     answer;      vKS          answer();    vKS
#     &answer;     vK/AMPER     &answer();   KS/AMPER
#
# AMPER without STACKED is the one that hands on the caller's @_. The graph
# built all four as a no-argument Call, so `&answer;` printed `[]` where
# perl prints `[1 2]`. Corpus 197.
round_trips(<<'SRC', 'the four call spellings');
sub answer { return "[@_]" }
sub outer {
    print answer, "\n";
    print answer(), "\n";
    print &answer, "\n";
    print &answer(), "\n";
}
outer(1, 2);
SRC

done_testing;
