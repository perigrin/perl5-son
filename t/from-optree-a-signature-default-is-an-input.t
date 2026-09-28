# ABOUTME: A signature parameter's default is part of the graph: the Parameter
# ABOUTME: takes the default's value as an input, and the emission applies it.

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
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>$dir/err);
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

# THE DEFAULT WAS NOWHERE. argdefelem is registered BRANCH with no handler,
# so the walk skipped it and the default expression in its ->other arm:
#
#     Parameter index=1 name=$b      and no 3 anywhere in the graph
#
# `add_up(1)` computed 1 + undef. Corpus 028.
round_trips(<<'SRC', 'a default applies when the argument is absent');
use v5.36;
sub add_up ($a, $b = 3) { $a + $b }
print add_up(1), " ", add_up(1, 10), "\n";
SRC

# ABSENT IS NOT UNDEF. `= 3` applies only when fewer arguments were passed;
# an explicit undef is an argument.
round_trips(<<'SRC', 'an explicit undef is not absent');
use v5.36;
no warnings 'uninitialized';
sub f ($a, $b = "dflt") { defined $b ? $b : "undef" }
print f(1), " ", f(1, undef), "\n";
SRC

# `//=` AND `||=` DEFAULTS (5.38) apply on undef and on false respectively,
# absent included.
round_trips(<<'SRC', 'the //= and ||= defaults');
use v5.38;
sub g ($a, $b //= 5, $c ||= 7) { "$b $c" }
print g(1), " | ", g(1, undef, 0), " | ", g(1, 2, 3), "\n";
SRC

# A DEFAULT IS AN EXPRESSION, and may read an earlier parameter.
round_trips(<<'SRC', 'a default that reads an earlier parameter');
use v5.36;
sub h ($a, $b = $a * 2) { "$a $b" }
print h(4), " ", h(4, 1), "\n";
SRC

done_testing;
