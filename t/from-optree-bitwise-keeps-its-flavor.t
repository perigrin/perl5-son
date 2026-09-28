# ABOUTME: Under the `bitwise` feature, & | ^ ~ are numeric and &. |. ^. ~. are
# ABOUTME: string; the graph records which, so the emission keeps the meaning.

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
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
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

# THREE OPS BECAME ONE NODE. bit_and (dual: string & string is string AND),
# nbit_and (numeric, under `use v5.28`) and sbit_and (`&.`) all mapped to
# BitAnd, and the emission -- which carries no feature -- spelled each as a
# dual `&`. On two strings that is a string AND. Corpus 045:
#
#     use v5.28; "12" & "10"     perl 8      emitted "10"
round_trips(<<'SRC', 'numeric bitwise ops on strings under the feature');
use v5.28;
my $a = $ENV{X} // "12";
my $b = $ENV{Y} // "10";
print $a & $b, " ", $a | $b, " ", $a ^ $b, " ", (~$a) & 0xFF, "\n";
SRC

round_trips(<<'SRC', 'string bitwise ops on numbers under the feature');
use v5.28;
my $a = $ENV{X} // 12;
my $b = $ENV{Y} // 10;
print $a &. $b, " ", $a |. $b, " ", $a ^. $b, "\n";
SRC

# WITHOUT THE FEATURE THE OP IS DUAL, and the emission's own `&` is the same
# operator -- nothing to coerce.
round_trips(<<'SRC', 'dual bitwise ops without the feature');
my $a = $ENV{X} // "12";
my $b = $ENV{Y} // "10";
print $a & $b, " ", 12 & $b, "\n";
SRC

done_testing;
