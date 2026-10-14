# ABOUTME: A bare loop condition is tested for truth as perl tests it: a string or an
# ABOUTME: object is true without being a nonzero number.

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


# The emission must also be QUIET: a second `my @e` in one scope is a "masks
# earlier declaration" warning, and the masked variable is the defect.
sub emits_quietly ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}


round_trips(<<'SRC', 'a while over strings that are not numbers');
my @a = ("abc", "x"); my $s = shift @a; my $n = 0; while ($s) { $n++; $s = shift @a } print "$n\n";
SRC

round_trips(<<'SRC', 'a compound condition over a string');
my @a = ("abc", "x"); my $s = shift @a; my $n = 0; while (defined $s && $s) { $n++; $s = shift @a } print "$n\n";
SRC

round_trips(<<'SRC', 'a while over a blessed object: the shape of chalk _pick_outer_return');
use Scalar::Util qw(blessed);
sub N::new { my ($c, %a) = @_; bless {%a}, $c } sub N::next { $_[0]{next} }
sub len_of { my $cur = shift; my $len = 0; while (defined $cur && blessed($cur)) { $len++; $cur = $cur->next } return $len }
my $c = N->new(next => N->new(next => N->new)); print len_of($c), len_of(undef), "\n";
SRC

round_trips(<<'SRC', 'a numeric countdown still tests against zero');
my $n = 3; my $c = 0; while ($n) { $n--; $c++ } print "$c\n";
SRC

done_testing;
