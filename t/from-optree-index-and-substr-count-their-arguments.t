# ABOUTME: index, rindex and substr take a variable number of arguments, and the
# ABOUTME: op's private field says how many -- a fixed pop drops the string.

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

# THE TABLE SAID 2 FOR ALL THREE. A 3-argument index popped the needle and the
# position and left the STRING on the stack, where the enclosing print picked
# it up as an argument of its own:
#
#     index($s, "o", 5)      rendered   $s, index("o", 5)
#
# Silent -- it compiles, and prints the string followed by -1. Corpus 141.
round_trips(<<'SRC', 'index with a position');
my $s = $ENV{X} // "hello world";
print index($s, "o", 5), "\n";
SRC

round_trips(<<'SRC', 'rindex with a position');
my $s = $ENV{X} // "hello world";
print rindex($s, "o", 5), "\n";
SRC

round_trips(<<'SRC', 'index without a position');
my $s = $ENV{X} // "hello world";
print index($s, "o"), "\n";
SRC

# COUNTING KIDS MISCOUNTS A NULLED ARGUMENT. substr already counted its kids,
# skipping every `null` to drop the folded pushmark -- but a package scalar
# argument is itself a null (ex-rv2sv over gvsv). Measured:
#
#     substr($s, 1, 2)         private=3  kids=[null,padsv,const,const]
#     substr($main::g, 1, 2)   private=3  kids=[null,null,const,const]
#
# so the package form counted 2 and left the string behind. The private
# field is right in both.
round_trips(<<'SRC', 'substr of a package scalar');
our $g = $ENV{X} // "hello";
print substr($main::g, 1, 2), "\n";
SRC

round_trips(<<'SRC', 'index of a package scalar with a position');
our $g = $ENV{X} // "hello";
print index($main::g, "l", 3), "\n";
SRC

done_testing;
