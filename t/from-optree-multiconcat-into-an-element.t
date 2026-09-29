# ABOUTME: An interpolation assigned to an element -- `$a[0] = "$x y"`, which
# ABOUTME: perl folds into a stacked multiconcat -- stores into the element.

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

# ONLY A PACKAGE-SCALAR DESTINATION WAS LOWERED. For an element the stack is
# [args..., destination] -- measured, the arg pop took the Subscript and the
# real operand ($ENV{M}) sat below it -- and the handler refused the whole
# program: "multiconcat storing into a stacked destination that is not a
# package scalar". Corpus 122.
round_trips(<<'SRC', 'an interpolation stored into an array element');
my @a = qw(x y z);
$a[0] = "$ENV{M}a";
print "@a\n";
SRC

round_trips(<<'SRC', 'an interpolation stored into a hash element');
my %h;
$h{k} = "x$ENV{M}y";
print "$h{k}\n";
SRC

done_testing;
