# ABOUTME: A call to a sub the program defines while running -- through a glob
# ABOUTME: assignment or its package's AUTOLOAD -- renders instead of refusing.

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

# THE REFUSAL WAS RIGHT ABOUT A NAME NOTHING DEFINES, and wrong about these:
# perl finds `missing` through AUTOLOAD, and `sq` through the CODE slot the
# glob assignment filled. Corpus 204, 202, and 011's tail.
round_trips(<<'SRC', 'a call resolved by AUTOLOAD');
our $AUTOLOAD;
sub AUTOLOAD { my $n = $AUTOLOAD; $n =~ s/.*:://; return "auto:$n" }
print missing(), "\n";
SRC

round_trips(<<'SRC', 'a call into a sub a glob assignment installed');
*sq = sub { $_[0] * $_[0] };
print sq(3), "\n";
SRC

# A SCALAR ASSIGN OF A PACKAGE VARIABLE. `my $n = $AUTOLOAD` is Assign(
# PadAccess, EntryDef); both kinds count as targets, and the Assign refused
# with "no values". A scalar assign is [target, value] by position.
round_trips(<<'SRC', 'a lexical assigned from a package scalar, then rewritten');
our $g = "Pkg::name";
my $n = $g;
$n =~ s/.*:://;
print "$n $g\n";
SRC

done_testing;
